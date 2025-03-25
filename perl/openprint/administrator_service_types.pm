use strict;
use warnings;

package openprint::administrator_service_types;

use openprint ();

require sql;
require openprint::logs;
require openprint::ServiceType;

use vars qw( $r $log $dbh %variable %param );
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*variable = \%openprint::variable;
*param = \%openprint::param;

sub edit {
	my $ServiceType = new openprint::ServiceType( $param{ServiceType_id} );

  if ( $param{btnFunction} ) {
    if ( $param{btnFunction} eq '<<' ) {
      $ServiceType = $ServiceType->Prev();
    } elsif ( $param{btnFunction} eq '>>' ) {
      $ServiceType = $ServiceType->Next();
    } elsif ( $param{btnFunction} eq 'Delete' ) {
      $variable{error} = $ServiceType->delete();
      if ( ! $variable{error} ) {
        $ServiceType = $ServiceType->Next() if ! $variable{error};
        (new openprint::Log())->save({action=>'Delete Service Type', note=> "Service Type ID: $$ServiceType{id} Name: $$ServiceType{name}"});
      } # end if
      if ( !$variable{error} ) {
        $variable{ExternalRedirect} = '/administrator/service_types/index.html';
      }
    } elsif ( $param{btnFunction} eq 'Destroy' ) {
      $variable{error} .= $ServiceType->destroy();
      if ( ! $variable{error} ) {
        (new openprint::Log())->save({
            action=>'Destroy Service Type',
            note=>"Service Type ID: $$ServiceType{id} Name: $$ServiceType{name}",
          });
        $ServiceType = $ServiceType->Next();
      } # end if
      if ( ! $variable{error} ) {
        $variable{ExternalRedirect} = '/administrator/service_types/index.html';
      }
    } elsif ( $param{btnFunction} eq 'Save' ) {
      if ( $param{new_category} ) {
        if ( my $Category = openprint::ServiceType_Category->find_one( name=>$param{new_category} ) ) {
          $param{category_id} = $Category->id();
        } else {
          my $Category = new openprint::ServiceType_Category();
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

      my @changes = $ServiceType->changes(\%param);
      if (@changes) {
        $_ = $ServiceType->save(\%param);
        $variable{error} .= "Error saving Service Type $$ServiceType{name} : $_<br/>" if $_;
      }

      if (!$variable{error}) {

        foreach my $SD ( $ServiceType->Defaults() ) {
          if ( ! $param{'name-'.$$SD{id}} ) {
            $variable{error} .= $SD->delete();
            push @changes, "Default $$SD{name} deleted";
          } else {
            my $changes = {
              projecttype_id	=>	$param{'projecttype_id-'.$$SD{id}},
              name						=>	$param{'name-'.$$SD{id}},
              value						=>	$param{'value-'.$$SD{id}},
              };
            my @sd_changes = $SD->changes($changes);
            if ( @sd_changes ) {
              $variable{error} .= $SD->save($changes) if @sd_changes;
              last if $variable{error};
              push @changes, @sd_changes;
            } # end if changes
          } # end if
        } # end foreach SD

        if ( $param{'name-'} ne '' ) {
          my $SD = new openprint::ServiceType_Default( );
          my $changes = {
              servicetype_id	=>	$$ServiceType{id},
              projecttype_id	=>	$param{'projecttype_id-'},
              name				=>	$param{'name-'},
              value				=>	$param{'value-'},
              };
          $variable{error} .= $SD->save($changes);
          push @changes, "New Default $$SD{name} " . join('<br/>', map { join('=>', $_, $$changes{$_}) } keys %{$changes}) if ! $variable{error};
        } # end if

      } # end if changes
      if (!$variable{error}) {
        (new openprint::Log())->save({ Object=>$ServiceType, action=>'Edit Service Type', note => join('<br/>', @changes ) });
        $variable{ExternalRedirect} = '/administrator/service_types/index.html';
      } else {
        $dbh->rollback();
      }
      sql::end_transaction($dbh, $ac);
    } elsif ( $param{btnFunction} eq 'Copy' ) {
      my $New = $ServiceType->copy();
      
      if ( $_ = $New->save({name=>'Copy of' . $New->name()}) ) {
        $variable{error} = $_;
      } else {
        foreach my $Default ( $ServiceType->Defaults() ) {
          $Default = $Default->copy();
          $variable{error} .= $Default->save({servicetype_id=>$New->id()});
          last if $variable{error};
        } # end foreach Default
        $ServiceType = $New;
      } # end if
    } elsif ( $param{btnFunction} eq 'Import' ) {
      if ( $param{fileImport} ) {
        my $upload = $r->upload( 'fileImport' );
        my $io = $upload->io();
        $_ = <$io>;

        my $csv = Text::CSV_XS->new();
        my %PT_cache = map { $_->name(), $_ } openprint::ProjectType->find();
        
        (new openprint::Log())->save({action=>'Import Service Type Defaults', note=> "Service Type ID: $$ServiceType{id} Name: $$ServiceType{name}"});
        
        my $ac = sql::start_transaction( $dbh );
        while ( <$io> ) {
          my $status = $csv->parse($_);
          my ( $project_type, $name, $value ) = misc::trim( $csv->fields() );
          
          my $PT = $PT_cache{$project_type};
          if ( $project_type and ! $PT ) {
            $variable{error} .= "No Project Type found for $project_type<br/>";
            next;
          }

          my $STD = new openprint::ServiceType_Default();
          if ( $_ = $STD->save({
                projecttype_id	=>	$PT ? $PT->id() : undef,
                servicetype_id	=>	$ServiceType->id(),
                name			=>	$name,
                value			=>	$value,
                }) ) {
            $variable{error} .= "Error saving Service Type Default $$ServiceType{id} : $_<br/>";
          } # end if
        } # end while <io>
        sql::end_transaction( $dbh, $ac );
        $ServiceType->Defaults( undef );
      } else {
        $log->warn('No file given to upload.');
      } # end if
    } elsif ( $param{btnFunction} eq 'Export' ) {
       my @header = ( 'Project Type', 'Name', 'Value' );
       my @data = map { $_->ProjectType()->name(), $_->name(), $_->value() } openprint::ServiceType_Default->find(servicetype_id=>$$ServiceType{id}, order=>$openprint::ServiceType_Default::fields{'name'});
      misc::export_csv( $r, $log, \%variable, $ServiceType->name().'_ServiceTypeDefaults.csv', \@header, \@data );
      # Add record to audit log - action "Export Project Types".
      (new openprint::Log())->save({
          action=>'Export Service Type Defaults',
          Object=>$ServiceType,
          note=> "Service Type ID: $$ServiceType{id} Name: $$ServiceType{name}"
        });
    } # end if
	} # end if btnfunction

	$variable{ServiceType} = $ServiceType;
} # end sub edit

sub _row {
	my $Default = new openprint::ServiceType_Default( $param{default_id} );
	if ( $param{action} eq 'delete' ) {
		$variable{error} .= $Default->delete();
	} elsif ( $param{action} eq 'copy' ) {
		$Default = $Default->copy();
		$variable{error} .= $Default->save();
	} # end if
	$variable{Default} = $Default;
} # end sub _row

sub index {
	 _index();
	 #if ( ( ! $session{'/administrator/service_types/index.html?lastupdated'} ) or ( time - $session{'/administrator/service_types/index.html?lastupdated'} ) > ( 12*60*60 ) ) {
			#ssi::setup_date_select( '/administrator/service_types/index.html', 'starting_on_start', 0 );
			#ssi::setup_date_select( '/administrator/service_types/index.html', 'starting_on_end', '' );
	 #} # end if
	if ( !$param{btnFunction} ) {
	} elsif ( $param{btnFunction} eq 'Export' ) {
		 my @header = ( 'Name', 'Description', 'Category', 'Type', 'URL', 'Visible in Project Create', 'Visible in Project View', 'Visible in Project Summary', 'Allow Removal', 'Sort Value' );
		 my @data = map { $_->get( qw(
					name 
					description	
					category		
					type			
					url			
					create_visible
					view_visible 
					summary_visible
					allow_delete	
					sorting		
					) )
		} openprint::ServiceType->find(order=>$openprint::ServiceType::fields{name});
	 	misc::export_csv( $r, $log, \%variable, 'ServiceTypes.csv', \@header, \@data );
	} elsif ( $param{btnFunction} eq 'Import' ) {
		my $error = '';
		if ( $param{fileImport} ) {
			my $upload = $r->upload('fileImport');
      if ( ! $upload ) {
        $variable{error} .= "No Upload for $param{fileImport}<br/>";
        return;
      }
			my $io = $upload->io();
			$_ = <$io>;

			my $csv = Text::CSV_XS->new();
			my %cache = map { $_->name(), $_ } openprint::ServiceType->find();
			
			my $ac = sql::start_transaction( $dbh );
			while ( <$io> ) {
				my $status = $csv->parse($_);
				my ( $name, $desc, $category, $type, $url, $visible_in_project_create, $visible_in_project_view, $visible_in_project_summary, $allow_removal, $sort ) = misc::trim( $csv->fields() );

				if ( ! $cache{$name} ) {
					$cache{$name} = new openprint::ServiceType();
				}
				my $ST = $cache{$name};

				my %changes = (
						name			=>	$name,
						description 	=>	$desc,
						category		=>	$category,
						type			=>	$type,
						url				=>	$url,
						create_visible	=>	$visible_in_project_create,
						view_visible	=>	$visible_in_project_view,
						summary_visible	=>	$visible_in_project_summary,
						allow_delete	=>	$allow_removal,		
						sorting			=>	$sort,
						);

				my @changes = $ST->changes( \%changes );

				if ( ! @changes ) {
					$variable{information} .= "No changes for $$ST{name}<br/>";
					next;
				}
				
				if ( $_ = $ST->save( \%changes ) ) {
					$error .= "Error saving Service Type $name : $_<br/>";
				} else {
					$variable{information} .= "ServiceType $name imported<br/>";
					(new openprint::Log())->save({
              Object=>$ST,
              action=>'Edit Service Type',
              note => join('<br/>', @changes ) });
				} # end if
			} # end foreach
			sql::end_transaction( $dbh, $ac );
		} else {
			$log->warn( "No file given to upload." );
		} # end if
		if ( $error ne '' ) {
			$variable{error} = $error;
		} # end if
	} elsif ( $param{btnFunction} eq 'Export Defaults' ) {
		my @header = ( 'Service Type', 'Project Type', 'Name', 'Value' );
		my @data;
		foreach my $ServiceType ( openprint::ServiceType->find(order=>'name') ) {
			push @data, map { $ServiceType->name(), $_->ProjectType()->name(), $_->name(), $_->value() } openprint::ServiceType_Default->find(servicetype_id=>$$ServiceType{id}, order=>$openprint::ServiceType_Default::fields{'name'});
		}
		misc::export_csv( $r, $log, \%variable, 'All_ServiceTypeDefaults.csv', \@header, \@data );
	} elsif ( $param{btnFunction} eq 'Import Defaults' ) {
		my $error = '';
		if ( $param{fileImport} ) {
			my $upload = $r->upload( 'fileImport' );
			my $io = $upload->io();
			$_ = <$io>;

			my $csv = Text::CSV_XS->new();
			my %servicetype_cache = map { $_->name(), $_ } openprint::ServiceType->find();
			my %projecttype_cache = map { $_->name(), $_ } openprint::ProjectType->find();
			
			my $ac = sql::start_transaction( $dbh );
			while ( <$io> ) {
				my $status = $csv->parse($_);
				my ( $service_type, $project_type, $name, $value ) = misc::trim( $csv->fields() );

				if ( ! $servicetype_cache{$service_type} ) {
					$variable{error} .= "ServiceType $service_type not found $project_type $name $value<br/>";
					next;
				}
				if ( $project_type and ! $projecttype_cache{$project_type} ) {
					$variable{error} .= "ProjectType $service_type not found $project_type $name $value<br/>";
					next;
				}
				my $cache = { map { $_->projecttype().$_->name() => $_ } $servicetype_cache{$service_type}->Defaults() };
				if ( ! $$cache{$project_type.$name} ) {
					$$cache{$project_type.$name} = new openprint::ServiceType_Default();
				}
				my $Default = $$cache{$project_type.$name};

				my %changes = (
						projecttype_id	=> $project_type ? $projecttype_cache{$project_type}->id() : undef,
						servicetype_id	=> $servicetype_cache{$service_type}->id(),
						name			=> $name,
						value			=> $value,
						);

				my @changes = $Default->changes( \%changes );

$log->debug("changes @changes");
				if ( ! @changes ) {
					$variable{information} .= "No changes for $$Default{name}<br/>";
$log->debug("No changes");
					next;
				}
				
				if ( $_ = $Default->save( \%changes ) ) {
					$error .= "Error saving Service Type Default $name : $_<br/>";
				} else {
					$variable{information} .= "Service Type Default $service_type $project_type $name $value imported<br/>";
					(new openprint::Log())->save({ Object=>$servicetype_cache{$service_type}, action=>'Edit', note => join('<br/>', @changes ) });
				} # end if
			} # end while io
			sql::end_transaction( $dbh, $ac );
			$variable{error} = $error;
		} else {
			$log->warn( "No file given to upload." );
		} # end if
	} # end if param{btnFunction}
} # end sub index

sub _index {
	 if ( ! $param{'btnFunction'} ) {
			ssi::save_params( '/administrator/service_types/index.html', (
					 #'starting_on_start_year','starting_on_start_month','starting_on_start_day',
					 #'starting_on_end_year','starting_on_end_month','starting_on_end_day',
					'category_id',
					) );
	 } # end if
}
sub categories {
	my $ServiceType_Category = new openprint::ServiceType_Category( $param{category_id} );
	$variable{ServiceType_Category} = $ServiceType_Category;
  return if ! $param{btnFunction};
	if ( $param{btnFunction} eq 'Save' ) {
		$variable{error} .= $ServiceType_Category->save(\%param);
    my @service_types = ref $param{servicetype_id} eq 'ARRAY' ? @{$param{servicetype_id}} : ($param{servicetype_id});
      
		foreach my $st_id (@service_types) {
      next if !$st_id;
			my $ServiceType = new openprint::ServiceType( $st_id );
			$variable{error} .= $ServiceType->save({ category_id=>$ServiceType_Category->id()});
		} # end foreach st_id
	} elsif ( $param{btnFunction} eq 'Delete' ) {
		$variable{error} .= $ServiceType_Category->delete();
  } else {
    $openprint::log->error("Unknown value for btnFunction $param{btnFunction}");
	} # end if
} # end sub categories

sub category {
	my $ServiceType_Category = $variable{ServiceType_Category} = new openprint::ServiceType_Category( $param{category_id} );
	if ( $param{btnFunction} eq 'Save' ) {
		$variable{error} .= $ServiceType_Category->save(\%param);
		foreach my $Type ( $ServiceType_Category->ServiceTypes() ) {
			next if sets::isin( $$Type{id}, $param{servicetype_id} );
			$variable{error} .= $Type->save({category_id=>undef});
		} # end if
    my @service_types = ref $param{servicetype_id} eq 'ARRAY' ? @{$param{servicetype_id}} : ($param{servicetype_id});
		foreach my $st_id ( @service_types ) {
      next if !$st_id;
			my $ServiceType = new openprint::ServiceType( $st_id );
			$variable{error} .= $ServiceType->save({ category_id=>$ServiceType_Category->id()});
		} # end foreach st_id
		$variable{ExternalRedirect} = '/administrator/service_types/categories.html' if ! $variable{error};
	} elsif ( $param{btnFunction} eq 'Delete' ) {
		$variable{error} .= $ServiceType_Category->delete();
		if ( ! $variable{error} ) {
			$variable{ExternalRedirect} = '/administrator/service_types/categories.html';
		}
	} # end if
} # end sub category

1;
__END__
