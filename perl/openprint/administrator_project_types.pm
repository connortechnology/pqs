package openprint::administrator_project_types;

use strict;
use warnings;

require openprint::ProjectType;
require openprint::ProjectTypeCategory;
require openprint::ProjectType_Default;
require openprint::ProjectType_Template;
require sql;
require misc;
require openprint::logs;

use openprint ();
use vars qw( $r $log $dbh %variable %param %session );
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*variable = \%openprint::variable;
*param = \%openprint::param;
*session = \%openprint::session;

sub edit {
  require openprint::Paper;
  require openprint::PaperPrice;

	my $ProjectType = new openprint::ProjectType( $param{ddmProjectType} );

  if ($param{btnFunction}) {
    if ( $param{btnFunction} eq 'Previous' ) {
      $ProjectType = $ProjectType->prev();
    } elsif ( $param{btnFunction} eq 'Next' ) {
      $ProjectType = $ProjectType->next();
    } elsif ( $param{btnFunction} eq 'Delete' ) {
      $variable{error} .= $ProjectType->delete();
      if ( ! $variable{error} ) {
        $ProjectType = $ProjectType->next();
        $variable{ExternalRedirect} = '/administrator/project_types/edit.html?ddmProjectType='.$ProjectType->id();
      } # end if
    } elsif ( $param{btnFunction} eq 'Copy' ) {
      my @recommendations = sql::execute(undef,undef,'SELECT lngPaperIndex FROM Paper_Recommendations WHERE lngProjectTypeIndex=?', $ProjectType->id() );

      $ProjectType = $ProjectType->copy();
      $ProjectType->name('Copy of ' . $ProjectType->name() );

      my @required_services = $ProjectType->required_services();
      my @blocked_services = $ProjectType->blocked_services();

      $variable{error} .= $ProjectType->save({required_services=>\@required_services, blocked_services=>\@blocked_services });

      foreach my $paper_id ( @recommendations ) {
        sql::insert( undef, undef, 'Paper_recommendations','lngPaperIndex',$paper_id,'lngProjectTypeIndex', $ProjectType->id() );
      } # end foreach
      $variable{ExternalRedirect} = '/administrator/project_types/edit.html?ddmProjectType='.$ProjectType->id();
    } elsif ( $param{btnFunction} eq 'Save' ) {
      if ( $param{category} ) {
        delete $param{category_id};
      } else {
        delete $param{category};
      }
      my @changes = $ProjectType->changes( \%param );
      $variable{error} .= $ProjectType->save( \%param );

      #sql::execute( undef, undef, 'DELETE FROM Paper_Recommendations WHERE lngProjectTypeIndex=?', $ProjectType->id() ) if $param{ddmProjectType};
      foreach my $key ( keys %param ) {
        if ( $key =~ /^paper_id(\d+)$/ ) {
          if (int($param{$key})) {
            sql::insert( undef, undef, 'Paper_recommendations','lngPaperIndex', $1, 'lngProjectTypeIndex', $ProjectType->id() );
          } else {
            sql::execute( undef, undef, 'DELETE FROM Paper_Recommendations WHERE lngProjectTypeIndex=? AND lngPaperIndex=?',
              $ProjectType->id(), $1 );
          } # end if
        } # end if
      } # end foreach
      (new openprint::Log())->save({
          Object=>$ProjectType, action=>($param{ddmProjectType}?'Edited ProjectType':'Saved ProjectType'), note=>join('<br/>', @changes) });
      $variable{ExternalRedirect} = '/administrator/project_types/edit.html?ddmProjectType='.$ProjectType->id();
    } elsif ( $param{btnFunction} eq 'Import' ) {
      my $error = '';
      if ( $param{fileImport} ) {
        my $upload = $r->upload('fileImport');
        if ( ! $upload ) {
          $variable{error} .= "No upload for file $param{fileImport}<br/>";
          return;
        }
        my $io = $upload->io();
        $_ = <$io>;

        my $csv = Text::CSV_XS->new();
        my %cache = map { $_->name(), $_ } openprint::ProjectType->find();


        my $ac = sql::start_transaction( $dbh );
        while ( <$io> ) {
          my $status = $csv->parse($_);
          my ( $name, $desc, $category, $url, $sort ) = misc::trim( $csv->fields() );

          if ( ! $cache{$name} ) {
            $cache{$name} = new openprint::ProjectType();
          }
          my $PT = $cache{$name};

          my %changes = (
            name        =>  $name,
            description =>  $desc,
            category	  =>	$category,
            url         =>  $url,
            sorting     =>  $sort,
          );

          my @changes = $PT->changes( \%changes );

          if ( ! @changes ) {
            $variable{information} .= "No changes for $$PT{name}<br/>";
            next;
          }

          if ( $_ .= $PT->save( \%changes ) ) {
            $error .= "Error saving Project Type $name : $_<br/>";
          } else {
            $variable{information} .=
            (new openprint::Log())->save({ Object=>$PT, action=>'Edit Project Type', note => join('<br/>', @changes ) });
          } # end if
        } # end foreach
        sql::end_transaction( $dbh, $ac );
        $variable{ExternalRedirect} = '/administrator/project_types/index.html';
      } else {
        $log->warn( "No file given to upload." );
      } # end if
      if ( $error ne '' ) {
        $variable{error} = $error;
      } # end if

    } elsif ( $param{btnFunction} eq 'Export' ) {
      my @header = ( 'Name', 'Description', 'Category', 'URL', 'Sort Order');
      my @data = map { $_->name(), $_->description(), $_->category(), $_->url(), $_->sorting() } openprint::ProjectType->find( order=>'sorting');
      misc::export_csv( $r, $log, \%variable, 'ProjectTypes.csv', \@header, \@data );
      # Add record to audit log - action "Export Project Types".
      #openprint::logs::insertLogRecord('40',);
    } # end if
  }
	$variable{ProjectType} = $ProjectType;
} # end sub edit

sub defaults_edit {
  return if ! $param{btnFunction};

	my $index = $param{ddmProjectType};

	if ( $param{btnFunction} eq 'Save' ) {

		my $ac = sql::start_transaction( $dbh );

		foreach my $Default ( openprint::ProjectType_Default->find( ( $index ? ( projecttype_id=>$index ) : () ) ) ) {
			if ( $param{"name-$$Default{id}"} ) {
				$variable{error} .= $Default->save({
					projecttype_id	=>	$param{"projecttype_id-$$Default{id}"},
					name			=>	$param{"name-$$Default{id}"},
					value			=>	$param{"name-$$Default{id}"},
				});
			} else {
				$variable{error} .= $Default->delete();
			} # end if
		} # end foreach
		if ( $param{'name-New'} ) {
			my $PTD = new openprint::ProjectType_Default( );
			$variable{error} .= $PTD->save({
					projecttype_id	=>	$param{'projecttype_id-New'},
					name			=>	$param{'name-New'},
					value			=>	$param{'value-New'},
					});
		} # end if
		sql::end_transaction( $dbh, $ac );
	} elsif ( $param{btnFunction} eq 'Import' ) {
		my $error = '';
		if ( $param{fileImport} ne '' ) {
			my $upload = $r->upload('fileImport');
			my $io = $upload->io();
			$_ = <$io>;
			my $csv = Text::CSV_XS->new();
			my $ac = sql::start_transaction( $dbh );
			my %cache = map { $_->name(), $_->id() } openprint::ProjectType->find();
			sql::execute( $log, $dbh, 'DELETE FROM projecttype_defaults' );

			while ( <$io> ) {
				my $status = $csv->parse($_);
				my ( $id, $name, $value ) = misc::trim( $csv->fields() );
				if ( $id ne '' and ! $cache{$id} ) {
					$error .= "Project Type $id not found.<br>";
					next;
				} # end if
				my $PTD = new openprint::ProjectType_Default();
				$error .= $PTD->save({
					'projecttype_id'	=>	( ( $id eq '' or $id eq 'All' ) ? undef : $cache{$id} ),
					'name'				=>	$name,
					'value'				=>	$value,
				});
			} # end foreach
			sql::end_transaction( $dbh, $ac );

		} else {
			$log->warn( "No file given to upload." );
		} # end if
		if ( $error ne '' ) {
			return misc::error( $log, $dbh, \%variable, 'Import errors.', $error );
		} # end if

	} elsif ( $param{btnFunction} eq 'Export' ) {
		my @header = ( 'Project Type ID', 'Field Name', 'Field Value');
		openprint::ProjectType->find();

		my @data = map { $_->ProjectType()->name(), $_->name(), $_->value() } openprint::ProjectType_Default->find('order'=>'projecttype_id NULLS FIRST, lower(name)');
		misc::export_csv( $r, $log, \%variable, 'ProjectTypes.csv', \@header, \@data );

	} # end if
} # end sub defaults_edit

sub templates {

	my $status = 'Error: ';

  return if !$param{btnFunction};
	if ( $param{btnFunction} eq 'Save' ) {
		my $ac = sql::start_transaction( $dbh );
		foreach my $Template ( openprint::ProjectType_Template->find( projecttype_id=>$param{ddmProjectType}) ) {
			$variable{error} .= $Template->save({
					type				=>	$param{"type$$Template{id}"},
					name				=>	$param{"name$$Template{id}"},
					description			=>	$param{"description$$Template{id}"},
					finished_width		=>	$param{"finishedwidth$$Template{id}"},
					finished_height		=>	$param{"finishedheight$$Template{id}"},
					flat_width			=>	$param{"flatwidth$$Template{id}"},
					flat_height			=>	$param{"flatheight$$Template{id}"},
					message				=>	$param{"message$$Template{id}"},
					} );
			if ( $variable{error} ) {
				$dbh->rollback();
				last;
			} # end if
			# Add record to audit log - action "Update Project Template".
			(new openprint::Log())->save({action=>'Update ProjectType Template', note=>"$$Template{type} - $$Template{description}" });
		} # end foreach Template
		if ( (!$variable{error}) and $param{typeNew} ) {
			$variable{error} .= new openprint::ProjectType_Template()->save({
					projecttype_id	=>	$param{ddmProjectType},
					type			=>	$param{typeNew},
					name			=>	$param{nameNew},
					description		=>	$param{descriptionNew},
					finished_width	=>	$param{finishedwidthNew},
					finished_height	=>	$param{finishedheightNew},
					flat_width		=>	$param{flatwidthNew},
					flat_height		=>	$param{flatheightNew},
					message			=>	$param{messageNew},
				} );
			# Add record to audit log - action "New Project Template".
			(new openprint::Log())->save({action=>'New ProjectType Template', note=>"$param{typeNew} - $param{descriptionNew}" });
		} # end if
		sql::end_transaction( $dbh, $ac );
	} elsif ( $param{btnFunction} eq 'Import Templates' ) {
		if ( $param{fileImport} ) {
			my $ac = sql::start_transaction( $dbh );
			my %project_types = map { $_->name(), $_->id() } openprint::ProjectType->find();

			if ( $param{ddmProjectType} ) {
				sql::execute( $log, $dbh, q{DELETE FROM ProjectTemplate WHERE ProjectType_id=?}, $param{ddmProjectType} );
			} else {
				sql::execute( $log, $dbh, q{DELETE FROM ProjectTemplate} );
			} # end if
			my $upload = $r->upload('fileImport');
			my $io = $upload->io();
			$_ = <$io>;
			my $csv = Text::CSV_XS->new();

			while ( <$io> ) {
				my $status = $csv->parse($_);
				my ( $projecttype_id, $id, $type, $name, $desc, $fwidth, $fheight, $width, $height );
				my @data = misc::trim( $csv->fields() );
				if ( @data == 8 ) {
					( $id, $type, $name, $desc, $fwidth, $fheight, $width, $height ) = @data;
				} elsif ( @data == 7 ) {
					( $type, $name, $desc, $fwidth, $fheight, $width, $height ) = @data;
				} else {
					$variable{error} .= "Wrong # of columns in input!<br/>";
					next;
				} # end if

				if ( $param{ddmProjectType} ) {
					$projecttype_id = $param{ddmProjectType};
				} else {
					$projecttype_id = $project_types{$id};
				} # end if

				if ( ! $projecttype_id ) {
					$variable{error} .= "Unknown Project Type $id<br/>";
					next;
				} # end if
				my @params = (
						'ProjectType_id',		$projecttype_id,
						'type',					$type,
						'name',					$name,
						'Description',			$desc,
						'dblFinishedWidth',		$fwidth * 1,
						'dblFinishedHeight',	$fheight * 1,
						'dblFlatWidth',			$width * 1,
						'dblFlatHeight',		$height * 1,
						);
				if ( ($_) = sql::insert( $log, $dbh, 'ProjectTemplate', @params ) ) {
					$variable{error} .= "Line Entry: $_<br/><br/>";
				} # end if
			} # for each
			sql::end_transaction( $dbh, $ac );
			$variable{ExternalRedirect} = '/administrator/project_types/templates.html?ddmProjectType='.$param{ddmProjectType};

		} else {
			$log->warn( "No file given to upload." );
		} # end if
	} elsif ( $param{btnFunction} eq 'Export Templates' ) {
		if ( $param{ddmProjectType} ) {
			my $ProjectType = new openprint::ProjectType( $param{ddmProjectType} );

			my @header = ( 'Template Type', 'Name', 'Description', 'Finished Width', 'Finished Height', 'Flat Width','Flat Height' );
			$_ = q{SELECT Type, Name, Description, dblFinishedWidth, dblFinishedHeight, dblFlatWidth, dblFlatHeight FROM ProjectTemplate WHERE projecttype_id=? ORDER BY Type};
			my @data = sql::execute( $log, $dbh, $_, $param{ddmProjectType} );
			misc::export_csv( $r, $log, \%variable, "Project Templates - $$ProjectType{name}.csv", \@header, \@data );
		} else {
			my @header = ( 'Project Type', 'Template Type', 'Name','Description', 'Finished Width', 'Finished Height', 'Flat Width','Flat Height' );
			$_ = q{SELECT (SELECT name FROM Project_Types WHERE id=ProjectType_id) AS ProjectType, Type, Name, Description, dblFinishedWidth, dblFinishedHeight, dblFlatWidth, dblFlatHeight FROM ProjectTemplate ORDER BY ProjectType,Type};
			my @data = sql::execute( $log, $dbh, $_ );
			misc::export_csv( $r, $log, \%variable, 'Project Templates - All.csv', \@header, \@data );
		} # end if

		# Add record to audit log - action "Export Project Templates".
		(new openprint::Log())->save({action=>'Export ProjectType Templates'});
	} # end if
} # end sub templates

sub _templates {
} # end sub _templates

sub _template_line {
	$variable{Template} = new openprint::ProjectType_Template( $param{template_id} );
	if ( $param{action} eq 'X' ) {
		if ( ! ( $variable{error} .= $variable{Template}->delete() ) ) {
			delete $variable{Template};
		} # end if
	} elsif ( $param{action} eq 'C' ) {
		$variable{Template} = $variable{Template}->copy();
		$variable{error} .= $variable{Template}->save();
	} # end if
} # end sub _template_line

sub _paper_recommendations {
	$variable{ProjectType} = new openprint::ProjectType( $param{projecttype_id} );
	if ( $param{btnFunction} eq 'Add' ) {
		sql::execute( undef, undef, 'DELETE FROM Paper_recommendations WHERE lngPaperIndex=? AND lngProjectTypeIndex=?', @param{'paper_id','projecttype_id'} );
		sql::insert( undef, undef, 'Paper_recommendations','lngPaperIndex',$param{paper_id},'lngProjectTypeIndex', $param{projecttype_id} );
	} elsif ( $param{btnFunction} eq 'Remove' ) {
		sql::execute( undef, undef, 'DELETE FROM Paper_recommendations WHERE lngPaperIndex=? AND lngProjectTypeIndex=?', @param{'paper_id','projecttype_id'} );
	} # end if
} # end sub _paper_recommendations

sub categories {
	my $ProjectTypeCategory = new openprint::ProjectTypeCategory( $param{category_id} );
  if ($param{btnFunction}) {
    if ( $param{btnFunction} eq 'Save' ) {
      $variable{error} .= $ProjectTypeCategory->save(\%param);
      foreach my $pt_id ( ref $param{projecttype_id} eq 'ARRAY' ? @{$param{projecttype_id}} : $param{projecttype_id} ) {
        my $ProjectType = new openprint::ProjectType( $pt_id );
        $variable{error} .= $ProjectType->save({category_id=>$ProjectTypeCategory->id()});
      } # end foreach pt_id
    } elsif ( $param{btnFunction} eq 'Delete' ) {
      $variable{error} .= $ProjectTypeCategory->delete();
    } # end if
  } # end if
	$variable{ProjectTypeCategory} = $ProjectTypeCategory;
} # end sub categories

sub category {
	my $ProjectTypeCategory = $variable{ProjectTypeCategory} = new openprint::ProjectTypeCategory( $param{category_id} );
	if ( $param{btnFunction} eq 'Save' ) {
		$variable{error} .= $ProjectTypeCategory->save(\%param);

    my %projecttype_ids = map { $_=>$_ } ( ref $param{projecttype_id} eq 'ARRAY' ? @{$param{projecttype_id}} : $param{projecttype_id} );

		foreach my $type ( $ProjectTypeCategory->ProjectTypes() ) {
			next if $projecttype_ids{$$type{id}};
			$variable{error} .= $type->save({category_id=>undef});
		} # end if
		foreach my $pt_id ( keys %projecttype_ids ) {
			my $ProjectType = openprint::ProjectType->find_one(id=> $pt_id);
      next if ! $ProjectType;
			$variable{error} .= $ProjectType->save({ category_id=>$ProjectTypeCategory->id()});
		} # end foreach pt_id
		$variable{ExternalRedirect} = '/administrator/project_types/categories.html' if ! $variable{error};
	} elsif ( $param{btnFunction} eq 'Delete' ) {
		$variable{error} .= $ProjectTypeCategory->delete();
		if ( ! $variable{error} ) {
			$variable{ExternalRedirect} = '/administrator/project_types/categories.html';
		}
	} # end if
} # end sub category

sub index {
	 _index();
	 #if ( ( ! $session{'/administrator/service_types/index.html?lastupdated'} ) or ( time - $session{'/administrator/service_types/index.html?lastupdated'} ) > ( 12*60*60 ) ) {
			#ssi::setup_date_select( '/administrator/service_types/index.html', 'starting_on_start', 0 );
			#ssi::setup_date_select( '/administrator/service_types/index.html', 'starting_on_end', '' );
	 #} # end if
  if ( $param{btnFunction} ) {
    if ( $param{btnFunction} eq 'Export' ) {
       my @header = ( 'Name', 'Description', 'Category', 'Type', 'URL', 'Sort Value' );
       my @data = map { $_->get( qw(
            name
            description
            category
            type
            url
            sorting
            ) )
      } openprint::ProjectType->find( order=>$openprint::ProjectType::fields{name});
      misc::export_csv( $r, $log, \%variable, 'ProjectTypes.csv', \@header, \@data );
    } elsif ( $param{btnFunction} eq 'Import' ) {
      my $error = '';
      if ( $param{fileImport} ) {
        my $upload = $r->upload('fileImport');
        my $io = $upload->io();
        $_ = <$io>;

        my $csv = Text::CSV_XS->new();
        my %cache = map { $_->name(), $_ } openprint::ProjectType->find();

        my $ac = sql::start_transaction( $dbh );
        while ( <$io> ) {
          my $status = $csv->parse($_);
          my ( $name, $desc, $category, $url, $sort ) = misc::trim( $csv->fields() );

          if ( ! $cache{$name} ) {
            $cache{$name} = new openprint::ProjectType();
          }
          my $PT = $cache{$name};

          my %changes = (
              name		  	=>	$name,
              description =>	$desc,
              category		=>	$category,
              url				  =>	$url,
              sorting			=>	$sort,
              );

          my @changes = $PT->changes( \%changes );

          if ( ! @changes ) {
            $variable{information} .= "No changes for $$PT{name}<br/>";
            next;
          }

          if ( $_ .= $PT->save( \%changes ) ) {
            $error .= "Error saving Service Type $name : $_<br/>";
          } else {
            $variable{information} .= "ProjectType $name imported<br/>";
            (new openprint::Log())->save({ Object=>$PT, action=>'Edit Project Type', note => join('<br/>', @changes ) });
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
        push @data, map { $ServiceType->name(), $_->ProjectType()->name(), $_->name(), $_->value() } openprint::ServiceType_Default->find(servicetype_id=>$$ServiceType{id}, order=>$openprint::ServiceType_Default::fields{name});
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
  } # end if param{btnFunction}
} # end sub search

sub _index {
	 if ( ! $param{btnFunction} ) {
			ssi::save_params( '/administrator/project_types/index.html', (
					 #'starting_on_start_year','starting_on_start_month','starting_on_start_day',
					 #'starting_on_end_year','starting_on_end_month','starting_on_end_day',
					'category_id',
					) );
	 } # end if
}

1;
__END__
