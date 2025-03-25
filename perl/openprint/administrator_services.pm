package openprint::administrator_services;

use strict;
use warnings;

require sql;
require openprint::Pricelist;
require openprint::Service;
require openprint::Timetrack;
require openprint::ServiceCategory;
require openprint::ServicePrice;
require openprint::logs;

use openprint ();
use vars qw( $r $log $dbh %param %variable );
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*param = \%openprint::param;
*variable = \%openprint::variable;

sub edit {
	my $Service = $variable{Service} = new openprint::Service( $param{service_id} );

  if ( $param{btnFunction} ) {
    if ( $param{btnFunction} eq '<<' ) {
      $Service = $Service->Previous( {category_id=>$param{ddmSearchCategory}} );
    } elsif ( $param{btnFunction} eq '>>' ) {
      $Service = $Service->Next( {category_id=>$param{ddmSearchCategory}} );
    } elsif ( $param{btnFunction} eq 'Delete' ) {
      $variable{error} .= $Service->delete() if ! $variable{error};
      $Service = $Service->Next( {category_id=>$param{ddmSearchCategory}} ) if ! $variable{error};
    } elsif ( $param{btnFunction} eq 'Undelete' ) {
      $variable{error} .= $Service->undelete() if ! $variable{error};
    } elsif ( $param{btnFunction} eq 'Destroy' ) {
      foreach my $T ( openprint::Timetrack->find(service_id=>$Service->id() ) ) {
        $variable{error} .= sprintf('Service is used in <a href="/timetrack/edit.html?timetrack_id=%1$d">Timetrack %1$d</a><br/>', $T->id() );
      } # end foreach T
      $variable{error} .= $Service->destroy() if ! $variable{error};
      $Service = $Service->Next( {category_id=>$param{ddmSearchCategory}} ) if ! $variable{error};
    } elsif ( $param{btnFunction} eq 'Export' ) {
      my @header = ( 'Service Name', 'Description','Category', 'Activity Code', 'Fed Tax Exempt', 'State Tax Exempt' );

      my @data;
      foreach ( openprint::Service->find( order=>'name' ) ) {
        push @data, $_->get( 'name', 'description', 'category', 'activity_code', 'taxexempt1','taxexempt2' );
      } # end foreach

      misc::export_csv( $openprint::r, $log, \%variable, 'services.csv', \@header, \@data );
    } elsif ( $param{btnFunction} eq 'Import' ) {

      my $error = '';
      if ( $param{file} ) {

        my $upload = $r->upload('file');
        if ( !$upload ) {
          $variable{error} .= "Failed import: no upload for $param{file}<br/>";
          return;
        }

        my $ac = sql::start_transaction( $dbh );
        my %Services = map { $$_{name}, $_ } openprint::Service->find();

        my $io = $upload->io();
        $_ = <$io>;

        my $csv = Text::CSV_XS->new();

        while (<$io>) {
          my $status = $csv->parse($_);
          my ( $name, $description, $category, $activity_code, $tax1, $tax2 ) = misc::trim( $csv->fields() );
          next if $name eq '';
          if ( $Services{$name} ) {
            $error .= "Not importing $name because it already exists at " . $Services{$name}->link_to().'<br/>';
            next;
          }
          my $Service = new openprint::Service();
          $_ = $Service->save({
              name			=>	$name,
              description		=>	$description,
              category		=>	$category,
              activity_code	=>	$activity_code,
              taxexempt1		=>	$tax1,
              taxexempt2		=>	$tax2,
            });
          if ( $_ ) {
            $error .= $_;
            $dbh->rollback();
            last;
          } else {
            $variable{information} .= "$name successfully imported.<br/>";
            $Services{$name} = $Service;
          }
        } # end while
        sql::end_transaction( $dbh, $ac );
      } else {
        $error .= 'No file given to upload.<br>';
      } # end if
      $variable{error} = $error; 
    } elsif ( $param{btnFunction} eq 'Save' ) {
      if ( $param{new_category} ) {
        if ( my @Categories = openprint::ServiceCategory->find(name=>$param{new_category} ) ) {
          $param{category_id} = $Categories[0]->id();
        } else {
          my $Category = new openprint::ServiceCategory();
          $Category->name( $param{new_category} );
          if ( $_ = $Category->save() ) {
            $variable{error} .= $_;
            return;
          } else {
            $param{category_id} = $Category->id();
          } # end if
        } # end if
      } # end if

      my $ac = sql::start_transaction( $dbh );
      my @changes = $Service->changes( \%param );
      $variable{error} = $Service->save( \%param ) if @changes;
      if (!$variable{error}) {
        # Please note that we don't do any deleting here.  We may only have the
        # prices for 1 piece of equipment on screen, so just update the ones that are on screen.

        @changes = ( join(', ', @changes) ) if @changes;
        foreach my $Price ( openprint::ServicePrice->find( 
            service_id=>$$Service{id}, 
            ($param{equipment_id} ? ( equipment_id=>$param{equipment_id} ) : () ),
            order=>'pricelist_id, min NULLS FIRST,max NULLS FIRST' ) ) {
          next if ! exists $param{"price-$$Price{id}"};
          my $new_values = {
            #equipment_id	=>	$param{"equipment_id-$$Price{id}"},
            period_start	=>	( Date::Calc::check_date( map { $param{"period_start-$$Price{id}_$_"} ? $param{"period_start-$$Price{id}_$_"} : 0 } ( 'year','month','day' ) ) ? sprintf('%.4d-%.2d-%.2d 00:00:00', map { $param{"period_start-$$Price{id}_$_"} } ( 'year','month','day' ) ) : undef ),
            period_end		=>	( Date::Calc::check_date( map { $param{"period_end-$$Price{id}_$_"} ? $param{"period_end-$$Price{id}_$_"} : 0} ( 'year','month','day' ) ) ? sprintf('%.4d-%.2d-%.2d 23:59:59', map { $param{"period_end-$$Price{id}_$_"} } ( 'year','month','day' ) ) : undef ),
            min				    =>	$param{"min-$$Price{id}"},
            max				    =>	$param{"max-$$Price{id}"},
            range_units		=>	$param{"range_units-$$Price{id}"},
            units			    =>	$param{"units-$$Price{id}"},
            cost			    =>	$param{"cost-$$Price{id}"},
            markup			  =>	$param{"markup-$$Price{id}"},
            price			    =>	$param{"price-$$Price{id}"},
            discountable	=>	$param{"discountable-$$Price{id}"},
            mode			    =>	$param{"mode-$$Price{id}"},
            supplier_id		=>	($param{"supplier_id-$$Price{id}"} ? $param{"supplier_id-$$Price{id}"} : undef)
          };
          my @price_changes = $Price->changes( $new_values );
          if ( @price_changes ) {
            $variable{error} .= $Price->save( $new_values );
            push @changes, ('Change price for ' .$Price->id_string() . ': ' .  join(', ', map { $_ } @price_changes));
          } # end if
        } # end foreach 
        (new openprint::Log())->save({Object=>$Service, action=>'Edit Service', note=>join('<br/>', @changes) }) if @changes;
      } # end if not error
      sql::end_transaction( $dbh, $ac );
      if ( ! $variable{error} ) {
        $variable{ExternalRedirect} = '/administrator/services/edit.html?service_id='.$Service->id();
        if ( $param{ddmServiceCategory} ) {
          $variable{ExternalRedirect} .= '&ddmServiceCategory='.$param{ddmServiceCategory};
        }
        if ( $param{equipment_id} ) {
          $variable{ExternalRedirect} .= '&equipment_id='.$param{equipment_id};
        } # end if
      } # end if
    } elsif ( $param{btnFunction} eq 'Copy' ) {

      my $NewService = $Service->copy();
      $$NewService{name} = 'Copy of '.$$Service{name};

      $variable{error} = $NewService->save();
      (new openprint::Log())->save({Object=>$NewService, action=>'Copy Service', note=>'From ' . $Service->name()} ) if ! $variable{error};
      if ( ! $variable{error} ) {
        foreach my $price ( $Service->prices() ) {
          $$price{service_id} = $$NewService{id};
          delete $$price{id};
          $variable{error} .= $price->save();
        } # end foreach
      } # end if
      $Service = $NewService;
    } # end if
  } # end if
	ssi::save_params($r->uri(), 'service_id', 'equipment_id', 'ddmSearchCategory');

	$variable{Service} = $Service;
} # end sub edit

sub _prices_table_body {
	if ( $param{action} eq 'add' ) {
		my $Service = $variable{Service} = new openprint::Service( $param{service_id} );
		my $Pricelist = $variable{Pricelist} = new openprint::Pricelist($param{pricelist_id});
		$variable{Equipment} = new openprint::Equipment( $param{equipment_id} );
		my $Price = $variable{Price} = new openprint::ServicePrice();
		$variable{error} .= $Price->save({ equipment_id=>$param{equipment_id}, pricelist_id=>$param{pricelist_id}, service_id=>$$Service{id} });
	} else {
		my $Price = new openprint::ServicePrice( $param{price_id} );
		$variable{Equipment} = $Price->Equipment();
		$variable{Pricelist} = $Price->Pricelist();
		my $Service = $variable{Service} = $Price->Service();
		if ( $param{action} eq 'copy' ) {
			$Price = $Price->copy();
			$variable{error} .= $Price->save();
		} elsif ( $param{action} eq 'delete' ) {
			$variable{error} .= $Price->delete();
			(new openprint::Log())->save({Object=>$Service, action=>'Delete Service Price', note=>$Price->id_string() }) if ! $variable{error};
		} # end if
	} # end if
	$variable{company_ids} = [ map { $_->id(), $_->name() } openprint::Company->find( supplier=>'Y', order=>'lower(name)' ) ];
} # end sub _prices_table_body

sub _price {
	$variable{Equipment} = new openprint::Equipment( $param{equipment_id} );
	$variable{Pricelist} = new openprint::Pricelist( $param{pricelist_id} );
	$variable{Service} = new openprint::Service( $param{service_id} );
	$variable{company_ids} = [ map { $_->id(), $_->name() } openprint::Company->find( supplier=>'Y', order=>'lower(name)' ) ];
	if ( $param{action} eq 'add' ) {
		my $Price = $variable{Price} = new openprint::ServicePrice();
		$variable{error} .= $Price->save({ equipment_id=>$param{equipment_id}, pricelist_id=>$param{pricelist_id}, service_id=>$param{service_id} });
	} # end if
} # end sub _price

sub _prices_per_equipment {
	$variable{Equipment} = new openprint::Equipment( $param{equipment_id} );
	$variable{Pricelist} = new openprint::Pricelist( $param{pricelist_id} );
	$variable{Service} = new openprint::Service( $param{service_id} );
	$variable{company_ids} = [ map { $_->id(), $_->name() } openprint::Company->find( supplier=>'Y', order=>'lower(name)' ) ];
	if ( $param{action} eq 'add' ) {
		my $Price = new openprint::ServicePrice();
		$variable{error} .= $Price->save({ equipment_id=>$param{equipment_id}, pricelist_id=>$param{pricelist_id}, service_id=>$param{service_id} });
	} # end if
} # end sub _prices_per_equipment

sub list {
  _list();
  $openprint::session{$r->uri().'?deleted'} = '0' if ! exists $openprint::session{$r->uri().'?deleted'};
}
sub _list {
  ssi::save_params( '/administrator/services/list.html', (
      'deleted', 'service_name', 'equipment_id', 'category_id','servicetype_id'
    ) );
  return if ! $param{btnFunction};

  if ($param{btnFunction} eq 'delete') {
    my @ids = ref $param{service_id} eq 'ARRAY' ? @{$param{service_id}} : ($param{service_id});
    foreach my $service ( openprint::Service->find(id=>\@ids, deleted=>[0,1]) ) {
      if ($service->deleted()) {
        $variable{error} .= $service->destroy();
      } else {
        $variable{error} .= $service->delete();
      }
    }
  }
}

1;
__END__
