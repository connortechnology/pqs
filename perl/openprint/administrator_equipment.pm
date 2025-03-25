use strict;
package openprint::administrator_equipment;

require Text::CSV_XS;
require sql;
require misc;

require openprint::Equipment_Category;
require openprint::Equipment_Operator;
require openprint::Equipment;
require openprint::EquipmentSpecification;
require openprint::Fold;
require openprint::FoldSpecification;
require openprint::logs;
require openprint;

use vars qw($r %variable $log $dbh %config %param );
*r = \$openprint::r;
*variable = \%openprint::variable;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*config = \%openprint::config;
*param = \%openprint::param;

sub import_specs {
	my ( $r, $Equipment ) = @_;

	my %equipment = map { $_->strid(), $_->id() } openprint::Equipment->find();

	my $error = '';
	if ( $param{fileSpecifications} ) {
		my $ac = sql::start_transaction( $dbh );

		sql::execute( undef, undef, 'DELETE FROM tbl_Equipment_Specifications' . ( $Equipment->id()?' WHERE lngEquipmentIndex=' . $Equipment->id():''));

		my $upload = $r->upload( 'fileSpecifications' );
		my $io = $upload->io();
		$_ = <$io>;

		my $csv = Text::CSV_XS->new();

		while (<$io>) {
			my $status = $csv->parse($_);
			my ( $id, $name, $min, $max, $units, $value, $interpolate ) = misc::trim( $csv->fields() );
			next if $id eq '';
			$min =~ s/[^\d\.]//;
			$max =~ s/[^\d\.]//;
			$interpolate = sets::isin( $interpolate, ['1','Y','true','TRUE'] ) ? 'true' : 'false';

			foreach my $equip_id ( misc::trim( split( ',', $id ) ) ) {
				if ( ! $equipment{$equip_id} ) {
					$error .= "Equipment $equip_id not found.<br>";
				} else {
					$error .= sql::insert( undef, undef, 'tbl_Equipment_Specifications', [
							'lngEquipmentIndex',    $equipment{$equip_id},
							'dblMin',               ( $min ne '' ? $min : undef ),
							'dblMax',               ( $max ne '' ? $max : undef ),
							'strUnits',             $units,
							'strName',              $name,
							'strValue',             $value,
							'interpolate',			$interpolate,
							] );
					#openprint::logs::insertLogRecord('37', "Equipment ID: " . $equipment{$equip_id} . " Name: " . $name . " Value: " . $value . " Units: " . $units,);
				} # end if
				last if $error;
			} # end for each
			last if $error;
		} # end while
		sql::end_transaction( $dbh, $ac );
	} else {
		$error .= 'No file given to upload.<br>';
	} # end if
	return $error;

} # end sub import_specs

sub export_specs {
	my ( $Equipment ) = @_;
	my @header = ( 'Equipment ID', 'Field Name','Min', 'Max', 'Units', 'Value','Interpolate' );

	my @data;
	foreach my $Spec ( openprint::EquipmentSpecification->find( equipment_id=>$Equipment->id(), order=>'strName, dblmin' ) ) {
		push @data, $Equipment->strid(), $Spec->name(), $Spec->min(), $Spec->max(), $Spec->units(), $Spec->value(), $Spec->interpolate();
	} # end foreach

	misc::export_csv( $r, $log, \%variable, 'equipment_specifications'.($Equipment->id()?'_'.$Equipment->strid():'').'.csv', \@header, \@data );
} # end sub export_specs

sub edit {
  require openprint::Estimating::Folding; # for fold_types
	my $Equipment = $variable{Equipment} = openprint::Equipment->find_one( id=>$param{ddmEquipment}, deleted=>[0,1] ) if $param{ddmEquipment};
	if ( ! $Equipment ) {
		$variable{error} .= "Equipment $param{ddmEquipment} not found.<br/>" if $param{ddmEquipment};
		$Equipment = new openprint::Equipment();
	}

  if ($param{btnFunction}) {
    if ( $param{btnFunction} eq 'Next' ) {
      $Equipment = $Equipment->Next();
    } elsif ( $param{btnFunction} eq 'Previous' ) {
      $Equipment = $Equipment->Previous();
    } elsif ( $param{btnFunction} eq 'Copy' ) {
      if ( $Equipment->id() ) {
        $Equipment = $Equipment->copy();
      } else {
        $variable{error} .= 'No equipment specified. No copy made.<br/>';
      }
      $param{ddmEquipment} = $Equipment->id();
    } elsif ( $param{btnFunction} eq 'Save' ) {
      $param{servicetype_id} = [ $param{servicetype_id} ] if ref $param{servicetype_id} ne 'ARRAY';
      $param{category_id} = [ $param{category_id} ] if ref $param{category_id} ne 'ARRAY';
      my @changes = $Equipment->changes( \%param );
      if (@changes) {
        if ( ! ( $variable{error} = $Equipment->save( \%param ) ) ) {
          (new openprint::Log())->save({ Object=>$Equipment, action=>($param{ddmEquipment}?'Edited Equipment':'Saved Equipment'), note=>join('<br/>', @changes) });
        }
      } else {
        (new openprint::Log())->save({ Object=>$Equipment, action=>'Edited Equipment', note=>'No changes' });
      }
      my %prices = misc::make_hash_from_array('service_id', openprint::ServicePrice->find(
            equipment_id=>$Equipment->id(),
            order=>'pricelist_id, min NULLS FIRST,max NULLS FIRST' ));
      foreach my $service (openprint::Service->find(id=>[keys %prices])) {
        my @service_changes;
        foreach my $Price ( @{$prices{$service->id()}} ) {
          next if ! exists $param{"price-$$Price{id}"};
          my $new_values = {
            period_start  =>  ( Date::Calc::check_date( map { $param{"period_start-$$Price{id}_$_"} ? $param{"period_start-$$Price{id}_$_"} : 0 } ( 'year','month','day' ) ) ? sprintf('%.4d-%.2d-%.2d 00:00:00', map { $param{"period_start-$$Price{id}_$_"} } ( 'year','month','day' ) ) : undef ),
            period_end    =>  ( Date::Calc::check_date( map { $param{"period_end-$$Price{id}_$_"} ? $param{"period_end-$$Price{id}_$_"} : 0} ( 'year','month','day' ) ) ? sprintf('%.4d-%.2d-%.2d 23:59:59', map { $param{"period_end-$$Price{id}_$_"} } ( 'year','month','day' ) ) : undef ),
            min           =>  $param{"min-$$Price{id}"},
            max           =>  $param{"max-$$Price{id}"},
            range_units   =>  $param{"range_units-$$Price{id}"},
            units         =>  $param{"units-$$Price{id}"},
            cost          =>  $param{"cost-$$Price{id}"},
            markup        =>  $param{"markup-$$Price{id}"},
            price         =>  $param{"price-$$Price{id}"},
            discountable  =>  $param{"discountable-$$Price{id}"},
            mode          =>  $param{"mode-$$Price{id}"},
            supplier_id   =>  ($param{"supplier_id-$$Price{id}"} ? $param{"supplier_id-$$Price{id}"} : undef)
          };
          my @price_changes = $Price->changes( $new_values );
          if ( @price_changes ) {
            $variable{error} .= $Price->save( $new_values );
            push @changes, ('Change price for ' .$Price->id_string() . ': ' .  join(', ', map { $_ } @price_changes));
            push @service_changes, ('Change price for ' .$Price->id_string() . ': ' .  join(', ', map { $_ } @price_changes));
          } # end if
        } # end foreach price
        (new openprint::Log())->save({Object=>$service, action=>'Edit Service', note=>join('<br/>', @service_changes) }) if @service_changes;
        (new openprint::Log())->save({Object=>$Equipment, action=>'Save', note=>join('<br/>', @service_changes) }) if @service_changes;
      } # end foreach service
      $variable{information} .= 'No changes made!<br/>' if !@changes;
      if (!$variable{errors}) {
        $variable{ExternalRedirect} = '/administrator/equipment/edit.html?ddmEquipment='.$Equipment->id();
      }
    } elsif ( $param{btnFunction} eq 'UnDelete' ) {
      $Equipment->undelete();
      $variable{ExternalRedirect} = '/administrator/equipment/list.html';
    } elsif ( $param{btnFunction} eq 'Delete' ) {
      $Equipment->delete();
      $variable{ExternalRedirect} = '/administrator/equipment/list.html';
    } elsif ( $param{btnFunction} eq 'Destroy' ) {
      $Equipment->destroy();
      $variable{ExternalRedirect} = '/administrator/equipment/list.html';
    } elsif ( $param{btnFunction} eq 'Import Specifications' ) {
      $variable{error} .= import_specs( $r, $Equipment );
    } elsif ( $param{btnFunction} eq 'Export Specifications' ) {
      export_specs( $Equipment );
    } elsif ( $param{btnFunction} eq 'Export Folds' ) {
      my @header = ( 'Equipment ID', 'Fold Type', 'Description', 'Pages', 'Horizontal Pages', 'Vertical Pages', 'Folds', 'Angles', 'Spine Direction', 'Min Imposition', 'Max Imposition', 'Min Page Width', 'Max Page Width', 'Min Page Height', 'Max Page Height', 'Min Calliper', 'Max Calliper', 'Printing Type', 'Make Ready Time', 'Make Ready Overs', 'Make Ready Units', 'Run Overs', 'Run Overs Units', 'Runspeed Units','Orientation', 'Inline Cutting', 'When Stitching', 'When Perfect Binding', 'Spine Pasting');

      my $max_speeds = 0;
      my @data;
      my @Folds = openprint::Fold->find( equipment_id=>$Equipment->id(), order=>'type, pages' );
      foreach my $Fold ( @Folds ) {
        my @Speeds = $Fold->Specifications();
        $max_speeds = scalar @Speeds if scalar @Speeds > $max_speeds;
      }
      foreach ( 1 .. $max_speeds ) {
        push @header, ( 'Min Weight', 'Max Weight', 'Units', 'Speed', 'Interpolate' );
      }

      foreach my $Fold ( @Folds ) {
        push @data, $Fold->Equipment()->strid(), $Fold->type(), $Fold->name(), 
        $Fold->pages(), $Fold->page_columns(), $Fold->page_rows(), 
        $Fold->folds(), $Fold->angles(), $Fold->spine_direction(), 
        $Fold->min_imposition(), $Fold->max_imposition(), 
        $Fold->min_width(), $Fold->max_width(), $Fold->min_height(), $Fold->max_height(), $Fold->min_calliper(), $Fold->max_calliper(), 
        $Fold->printing_type(), $Fold->makeready_time(), $Fold->makeready_overs(), $Fold->makeready_overs_units(), 
        $Fold->run_overs(), $Fold->run_overs_units(), 
        $Fold->runspeed_units(),
        $Fold->orientation(),
        $Fold->cutting(), $Fold->stitching(), $Fold->perfectbind(), $Fold->spinepaste();
        my @Speeds = $Fold->Specifications();
        my $speeds = scalar @Speeds;

        foreach my $Speed ( @Speeds ) {
          push @data, $Speed->min(), $Speed->max(), $Speed->units(), $Speed->runspeed(), $Speed->interpolate();
        } # end foreach	Speed
        foreach ( 1 .. ($max_speeds - $speeds ) ) {
          push @data, '','','','','';
        }
      } # end foreach Fold

      misc::export_csv( $r, $log, \%variable, 'fold_definitions'.($Equipment->id()?'_'.$Equipment->strid():'').'.csv', \@header, \@data );
      (new openprint::Log())->save({ action=>'Export Fold Definitions' });
    } elsif ( $param{btnFunction} eq 'Export Service Prices' ) {
      my @header = ( 'Service ID', 'Equipment ID','Min', 'Max', 'Units', 'Cost', 'Markup', 'Price', 'Discountable' );
      my @data = map {
        $_->Service()->name(), $_->Equipment()->strid(), $_->min(), $_->max(), $_->units(), $_->cost(), $_->markup(), $_->price(), $_->discountable()
      } openprint::ServicePrice->find( equipment_id=>$Equipment->id(), order=>join(',',@openprint::ServicePrice::fields{'min','max'}));
      misc::export_csv( $r, $log, \%variable, $Equipment->strid() . 'ServicePrices.csv', \@header, \@data );

    } elsif ( $param{btnFunction} eq 'Import Folds' ) {
      my %equipment = map { $_->strid(), $_->id() } openprint::Equipment->find();
      # if ! $Equipment->id();

      my $error = '';
      if ( ! $param{fileFolds} ) {
        $variable{error} .= 'No file given to upload.<br>';
        return;
      } # end if

      my $ac = sql::start_transaction( $dbh );

      sql::execute( undef, undef, 'DELETE FROM Fold_Specifications WHERE fold_id IN (SELECT id FROM Folds ' . ( $Equipment->id()?' WHERE equipment_id=' . $Equipment->id():'').')');
      sql::execute( undef, undef, 'DELETE FROM Folds' . ( $Equipment->id()?' WHERE equipment_id=' . $Equipment->id():''));

      my $upload = $r->upload('fileFolds');
      my $io = $upload->io();
      $_ = <$io>;

      my $csv = Text::CSV_XS->new();

      while (<$io>) {
        my $status = $csv->parse($_);
        my ( $equipment_strid, $type, $name, $pages, $page_columns, $page_rows, $folds, $angles, $spine_direction, 
          $min_imposition, $max_imposition, $min_width, $max_width, $min_height, $max_height, 
          $min_calliper, $max_calliper, 
          $printing_type, $makeready_time, $makeready_overs, $makeready_overs_units, $run_overs, $run_overs_units, 
          $runspeed_units, $orientation,
          $cutting, $stitching, $perfectbind, $spinepaste, @speeds )
        = misc::trim( $csv->fields() );

        if ( ! $equipment{$equipment_strid} ) {
          $error .= "Equipment $equipment_strid not found.<br>";
          $log->error($error);
          next;
        } 
        my $Fold = new openprint::Fold();
        $error .= $Fold->save({
            equipment_id          =>  $equipment{$equipment_strid},
            type                  =>  $type,
            name                  =>  $name,
            min_width             =>  $min_width,
            max_width             =>  $max_width,
            min_height            =>  $min_height,
            max_height            =>  $max_height,
            min_calliper          =>  $min_calliper,
            max_calliper          =>  $max_calliper,
            pages                 =>  $pages,
            page_columns          =>  $page_columns,
            page_rows             =>  $page_rows,
            min_imposition        =>  $min_imposition,
            max_imposition        =>  $max_imposition,
            runspeed_units				=>	$runspeed_units,
            orientation						=>	$orientation,	
            cutting               =>  $cutting,
            stitching             =>  $stitching,
            perfectbind           =>  $perfectbind,
            spinepaste            =>  $spinepaste,
            spine_direction       =>  $spine_direction,
            makeready_time        =>  $makeready_time,
            makeready_overs       =>  $makeready_overs,
            makeready_overs_units =>  $makeready_overs_units,
            run_overs_units       =>  $run_overs_units,
            run_overs             =>  $run_overs,
            folds                 =>  $folds,
            angles                =>  $angles,
            printing_type         =>  $printing_type,
          });
        if ( $error ) {
          $dbh->rollback();
          last;
        }
        while ( my ( $min_weight, $max_weight, $weight_units, $runspeed, $interpolate ) = splice @speeds, 0, 5 ) {
          next if ! $runspeed;
          my $Speed =  new openprint::FoldSpecification();
          $error .= $Speed->save({
              fold_id       =>  $$Fold{id},
              min_weight    =>  $min_weight,
              max_weight    =>  $max_weight,
              weight_units  =>  $weight_units,
              runspeed      =>  $runspeed,
              interpolate   =>  $interpolate,
            });

        } # end while speeds

      } # end while IO
      sql::end_transaction( $dbh, $ac );
      $variable{error} = $error;
	} elsif ( $param{btnFunction} eq 'Import Service Prices' ) {
		$variable{error} .= 'You must select equipment before importing.<br/>' if ! $Equipment->id();
		$variable{error} .= 'You must select a file to import.<br/>' if ! $param{fileServicePrices};
    return if $variable{error};

		my $error = '';
		my $ac = sql::start_transaction( $dbh );

		# An import replaces the current pricelist, so delete verything in the current one.
		sql::execute( $log, $dbh, 'DELETE FROM Service_Prices WHERE equipment_id=?', $Equipment->id() );

		# get the upload.
		my $upload = $r->upload( 'fileServicePrices' );
		my $io = $upload->io();
		$_ = <$io>;
		my $csv = Text::CSV_XS->new();
		my %services = map { $_->name(), $_ } openprint::Service->find();
		my %equipment= map { $_->strid(), $_ } openprint::Equipment->find();

		while ( <$io> ) {
			my $status = $csv->parse($_);
			my ( $name, $equip_ids, $min,$max,$units, $cost, $markup, $price, $discountable ) = $csv->fields();
			$name = openprint::Service->transform( name => $name );
			next if $name eq '';

			my $service = $services{$name};
			if (!$service) {
        $service = $services{$name} = new openprint::Service();
        $service->save({name=>$name, description=>$name});
			} # end if

			foreach my $equip_id ( split(',', $equip_ids ) ) {
				$equip_id = openprint::Equipment->transform( strid => $equip_id );
				if ( ! $equipment{$equip_id} ) {
					$error .= "No Equipment found for $equip_id<br>";
					next;
				} # end if
        if ($equip_id ne $Equipment->strid()) {
					$error .= "Doesnt match selected equipment: $equip_id<br>";
					next;
				} # end if

        foreach my $Pricelist (openprint::Pricelist->find()) {
          my $Price = new openprint::ServicePrice();
          $_ = $Price->save({
              pricelist_id	=>	$Pricelist->id(),
              service_id		=>	$service->id(),
              equipment_id	=>	$equip_id ? $equipment{$equip_id}->id() : undef,
              min				=>	$min,
              max				=>	$max,
              units			=>	$units,
              cost			=>	$cost,
              price			=>	$price,
              discountable	=>	$discountable,
            });
          if ( $_ ) {
            $error .= $_ . " for $services{$name}\n";
          } else {
            $variable{information} .= "Added Price for service $name on $equip_id $min - $max $units $cost $markup $price<br/>";
          }
        }
			} # end foreach equipment_id
		} # end while IO
		sql::end_transaction( $openprint::dbh, $ac );
		$variable{error} .= $error;
    } # end if
  } # end if btnFunction

	$variable{Equipment} = $Equipment;
} # end sub equipment_edit

sub _specification {
	my $Specification = new openprint::EquipmentSpecification( $param{id} );
	my $Equipment = $Specification->Equipment();

	if ( $param{action} eq 'add' ) {
		$variable{error} .= $Specification->save({ name=>'new', equipment_id=>$param{equipment_id}});
	} elsif ( $param{action} eq 'delete' ) {
		if ( ! $Specification->delete() ) {
			(new openprint::Log())->save({ Object=>$Equipment, action=>'Delete Equipment Specification', 
				note=>join(' => ' , @$Specification{'name','value'} ) });
			$variable{PageContent} = ' ';
		}
	} elsif ( $param{action} eq 'copy' ) {
		$Specification = $Specification->copy();
		$Specification->save();
	} elsif ( $param{action} eq 'update' ) {
		if ( $param{field} ne 'interpolate' ) {
			$param{value} =~ s/\xc2\xa0//mg;
			if ( $param{field} eq 'name' ) {
				$param{value} =~ s/\+/ /g;
			} elsif ( $param{field} eq 'min' ) {
				$param{value} =~ s/[^\d\.]//g;
			} elsif ( $param{field} eq 'max' ) {
				$param{value} =~ s/[^\d\.]//g;
			} elsif ( $param{field} eq 'value' ) {
				$param{value} = ssi::unhtmlize( $param{value} );
			} elsif ( $param{field} eq 'units' ) {
			} # end if

			my @changes = $Specification->changes({ $param{field} => $param{value} });
			if ( @changes ) {
				(new openprint::Log())->save({ Object=>$Equipment, action=>'Save Equipment Specification', 
				note=>$$Specification{name} . ' ' .join('<br/>', @changes )
				});
#. $param{field} . ' from ' . join(' => ' , $$Specification{$param{field}}, $param{value} ) });
			$variable{error} .= $Specification->save({$param{field}=>$param{value}});
			}
			$variable{PageContent} = $$Specification{$param{field}} ne '' ? $$Specification{$param{field}} : '&nbsp;';
		} else {
			$$Specification{interpolate} = ! $$Specification{interpolate};
			$$Specification{interpolate} = 1 * $$Specification{interpolate};
			$Specification->save();
			$variable{PageContent} = $$Specification{interpolate} ? 'Yes' : 'No';
		} # end if
	} # end if
	$variable{Specification} = $Specification;
} # end sub _specification

sub _fold {
  require openprint::Estimating::Folding; # for fold_types
	my $Fold = new openprint::Fold( $param{id} );
	if ( $param{action} eq 'add' ) {
		foreach my $k ( 'equipment_id' ) {
			$$Fold{$k} = $param{$k};
		} # end foreach
		$Fold->save();
		$variable{Fold} = $Fold;
	} elsif ( $param{action} eq 'copy' ) {
		my $NewFold = $Fold->copy();
		delete $param{id};
		$variable{error} .= $NewFold->save(\%param);
		if ( ! $variable{error} ) {
		foreach my $Spec ( $NewFold->Specifications() ) {
			$_ = $Spec->save( {fold_id=>$NewFold->id() });
		} # end foreach Spec
		}
		$variable{Fold} = $NewFold;
		$param{id} = $NewFold->id();
		
	} elsif ( $param{action} eq 'save' ) {
		my @changes = $Fold->changes( \%param );
		$variable{error} = $Fold->save(\%param);
		if ( ! $variable{error} ) {
			my $Equipment = $Fold->Equipment();
			(new openprint::Log())->save({ object_type=>(ref $Equipment), object_id=>$$Equipment{id}, action=>'Save Fold', 
				note=>$$Fold{name} . ' ' . join('<br/>', @changes ) });
		} # end if
		$variable{Fold} = $Fold;
	} elsif ( $param{action} eq 'delete' ) {
		$Fold->delete();
		$variable{PageContent} = ' ';
	} # end if
} # end sub _fold

sub _fold_specification {
	my $FoldSpecification = new openprint::FoldSpecification( $param{id} );
	my $Fold = $FoldSpecification->Fold();
	my $Equipment = $Fold->Equipment();

	if ( $param{action} eq 'add' ) {
		foreach my $k ( 'fold_id' ) {
			$$FoldSpecification{$k} = $param{$k};
		} # end foreach
		$FoldSpecification->save();
		$variable{Specification} = $FoldSpecification;
	} elsif ( $param{action} eq 'delete' ) {
		$FoldSpecification->delete();
			(new openprint::Log())->save({ object_type=>(ref $Equipment), object_id=>$$Equipment{id}, action=>'Save Fold', note=>'Fold ' . $$Fold{name} . ' specification deleted ' . $FoldSpecification->to_string() });
		$variable{PageContent} = ' ';
	} elsif ( $param{action} eq 'update' ) {
		if ( $param{field} ne 'interpolate' ) {
			(new openprint::Log())->save({ object_type=>(ref $Equipment), object_id=>$$Equipment{id}, action=>'Save Fold', note=>'Fold ' . $$Fold{name} . ' specification ' . $param{field} . ' changed from ' . $$FoldSpecification{$param{field}} . ' to ' . $param{value} });
			$$FoldSpecification{$param{field}} = $param{value};
			$FoldSpecification->save();
			$variable{PageContent} = $$FoldSpecification{$param{field}};
		} else {
			(new openprint::Log())->save({ object_type=>(ref $Equipment), object_id=>$$Equipment{id}, action=>'Save Fold', note=>'Fold ' . $$Fold{name} . ' specification ' . $param{field} . ' changed from ' . $$FoldSpecification{$param{field}} . ' to ' . $param{value} });
			$$FoldSpecification{interpolate} = ! $$FoldSpecification{interpolate};
			$$FoldSpecification{interpolate} = 1 * $$FoldSpecification{interpolate};
			$FoldSpecification->save();
			$variable{PageContent} = $$FoldSpecification{interpolate} ? 'Yes' : 'No';
		} # end if
	} # end if
} # end sub _fold_specification

sub _stock_setting_popup {
	$variable{Equipment} = new openprint::Equipment( $param{equipment_id} );
} # end sub _stock_settings_popup

sub _stocks {
	$variable{Equipment} = new openprint::Equipment( $param{equipment_id} );
	if ( $param{action} eq 'add' ) {
		my $Setting = new openprint::Equipment_Stock_Setting();
		$variable{error} .= $Setting->save(\%param);
		%param = ();
	} # end if
	ssi::save_params('/administrator/equipment/edit.html', 'Group','Manufacturer','Name','Finish','Colour','Weight','Types', 'material_id' );
} # end sub _stocks

sub _stock_settings {
	$variable{Equipment} = new openprint::Equipment( $param{equipment_id} );
	if ( $param{action} eq 'delete' ) {
		my $Setting = new openprint::Equipment_Stock_Setting( $param{id} );
		$variable{error} .= $Setting->delete();
		%param = ();
	} elsif ( $param{action} eq 'save' ) {
		foreach my $Setting ( $variable{Equipment}->Stock_Settings() ) {
			$variable{error} .= $Setting->save({'grain'=>$param{"grain_$$Setting{id}"}});
		} # end foreach Setting
		%param = ();
	} # end if
} # end sub _stock_settings

sub _operators {
	my $Equipment = $variable{Equipment} = new openprint::Equipment( $param{equipment_id} );
	if ( $param{action} eq 'delete' ) {
		my $EO = new openprint::Equipment_Operator( { equipment_id=>$param{equipment_id}, user_id=>$param{user_id} } );
		$variable{error} .= $EO->delete();
	} elsif ( $param{action} eq 'add' ) {
		my $EO = new openprint::Equipment_Operator();
		$variable{error} .= $EO->save( { equipment_id=>$param{equipment_id}, user_id=>$param{user_id} } );
	} # end if
} # end sub _operators

sub list {
	_list();
	ssi::setup_date_select( '/administrator/equipment/list.html', 'created_on_start', '' );
	ssi::setup_date_select( '/administrator/equipment/list.html', 'created_on_end', '' );
	$openprint::session{'/administrator/equipment/list.html?deleted'} = '0' if ! exists $openprint::session{'/administrator/equipment/list.html?deleted'};
}
sub _list {
    ssi::save_params( '/administrator/equipment/list.html', (
                ( map { 'created_on_start_' . $_ } ( 'year','month','day' ) ),
				'deleted', 'equipment_name', 'servicetype_id', 'category_id', 'useinestimating',
                ) );
}

sub _service_prices {
  $variable{Equipment} = new openprint::Equipment($param{equipment_id});
  if ($param{hide} eq '1') {
    $openprint::session{'/administrator/equipment/edit.html?show_service_prices'} = 0;
    $variable{PageContent} = '';
  } else  {
    $openprint::session{'/administrator/equipment/edit.html?show_service_prices'} = 1;
  }
}

1;
__END__
