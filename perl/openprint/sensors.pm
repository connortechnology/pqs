use strict;
use warnings;
package openprint::sensors;

use openprint ();
use vars qw($r $log $dbh %variable %param %session);
*r = \$openprint::r;
*variable = \%openprint::variable;
*param = \%openprint::param;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*session = \%openprint::session;

require EnviroTrack::Sensor;
require EnviroTrack::Sensor_Reading;
require EnviroTrack::Sensor_Input;
require EnviroTrack::Sensor_Type;
require sql;

sub view {
	$param{sensor_id} = EnviroTrack::Sensor->transform( 'id', $param{sensor_id} );
	my $Sensor = $variable{Sensor} = new EnviroTrack::Sensor( $param{sensor_id} );
	if ( $param{sensor_id} and ! $Sensor->id() ) {
		$variable{error} .= "Sensor $param{sensor_id} not found.<br/>";
	} # end if
	if ( $param{action} eq 'Delete' ) {
		if ( ! ( $variable{error} .= $Sensor->delete() ) ) {
			$variable{information} .= 'Sensor deleted successfully.';
			$Sensor = $variable{Sensor} = $Sensor->next();
		} # end if
	}
} # end sub view

sub edit {
	my $Sensor = $variable{Sensor} = new EnviroTrack::Sensor( $param{sensor_id} );

	if ( $param{action} ) {
		if ( $param{action} eq 'Save' ) {
			if ( (! $param{sensor_id}) and EnviroTrack::Sensor->find( 'name lc' => lc EnviroTrack::Sensor->transform('name',$param{name}) ) ) {
				$variable{error} = "A sensor with name $param{name} already exists.	Please choose another name.";
				return;
			} # end if
			foreach my $toggle ( 'type' ) {
				if ( !$param{$toggle} ) {
					delete $param{"${toggle}_id"};
				} else {
					delete $param{$toggle};
				}
			}
			my @changes = $Sensor->changes( \%param );
			if ( @changes ) {
				$variable{error} = $Sensor->save( \%param );
			}
		#if ( $param{sensor_id} ) {
			# Save the prices
		#_prices();
		#my @spec_changes = openprint::Object_Specification::save_changes( $Sensor, \%param );
		#push @changes, 'specification changes: ' . join(', ', @spec_changes ) if @spec_changes;

		#} # end if
			( new openprint::Log())->save({Object=>$Sensor, action=>($param{sensor_id} ? 'Edit' : 'Create' ), note=>join('<br/>', @changes ) } ) if @changes;
			$param{action} = '';
			$variable{ExternalRedirect} = '/sensors/edit.html?sensor_id='.$Sensor->id();
		} elsif ( $param{action} eq 'Copy' ) {
			my $NewSensor = $Sensor->copy();
			$NewSensor->save();

			(new openprint::Log())->save({action=>'Copy', note=>'New Sensor ID: ' . $NewSensor->id() . ' Name: ' . $NewSensor->name(), Object=>$Sensor });
			(new openprint::Log())->save({action=>'Copy', note=>'Original Sensor ID: ' . $param{sensor_id} . ' Name: ' . $Sensor->name(), Object=>$NewSensor });

		#foreach my $Price ( EnviroTrack::SensorPrice->find( sensor_id => $param{sensor_id} ) ) {
		#$$Price{sensor_id} = $NewSensor->id();
		#$$Price{id} = undef;
		#$Price->save();
		#} # end foreach
		#foreach ( $NewSensor->Specifications() ) {
		#$_->save({object_id => $$NewSensor{id} });
		#}
			$Sensor = $NewSensor;

		} elsif ( $param{action} eq 'Delete' ) {
			if ( ! ( $variable{error} .= $Sensor->delete() ) ) {
				$variable{information} .= 'Sensor deleted successfully.';
				$Sensor = $Sensor->next();
			} # end if
		} elsif ( $param{action} eq '>>' ) {
			$Sensor = $Sensor->next();
		} elsif ( $param{action} eq '<<' ) {
			$Sensor = $Sensor->previous();
		} elsif ( $param{action} eq 'Export Definitions' ) {
			my @header = ( 'Name', 'Description','Category', 'Tax Exempt 1','Tax Exempt2', 'Sort Order');
			my @data = sql::execute( $log, $dbh, 'SELECT name, description, (SELECT name from sensor_categories where id=category_id), taxexempt1, taxexempt2, sort FROM Sensors ORDER BY sort' );
			misc::export_csv( $r, $log, \%variable, 'Sensors.csv', \@header, \@data );
		} elsif ( $param{action} eq 'Import Definitions' ) {
			my $error = '';
			if ( $param{fileImport} ) {
				my $upload = $r->upload( 'fileImport' );
				my $io = $upload->io();
				$_ = <$io>;

				my $csv = Text::CSV_XS->new();
				my $ac = sql::start_transaction( $dbh );
				my %categories = map { $_->name(), $_ } EnviroTrack::Sensor_Category->find();
				my %sensors = map { $_->name(), $_ } EnviroTrack::Sensor->find();
				
				while ( <$io> ) {
					my $status = $csv->parse($_);
					my ( $name, $description, $category, $taxexempt1, $taxexempt2, $sort ) = misc::trim( $csv->fields() );
					next if ! $name;
					if ( $category and ! $categories{$category} ) {
						$categories{$category} = new EnviroTrack::Sensor_Category();
						$categories{$category}->name( $category );
						$categories{$category}->save();
					} # end if
					my %sql = (
						'name'			=>	$name,
						'description'	=>	$description,
						'category_id'	=>	$category ? $categories{$category}->id() : undef,
						'taxexempt1'	=>	$taxexempt1,
						'taxexempt2'	=>	$taxexempt2,
						'sort'			=>	$sort,
					);
					my $Sensor = $sensors{$name} ? $sensors{$name} : new EnviroTrack::Sensor();
					$error .= $Sensor->save( \%sql );
				} # end while
				sql::end_transaction( $dbh, $ac );
			} else {
				$log->warn( "No file given to upload." );
			} # end if
			if ( $error ne '' ) {
				return misc::error( $log, $dbh, \%variable, 'Import errors.', $error );
			} # end if
		} elsif ( $param{action} eq 'Export Specifications' ) {
			my @header = ( 'Sensor', 'Name','Value');
			my @data;
			foreach my $Sensor ( EnviroTrack::Sensor->find() ) {
				foreach my $Spec ( $Sensor->Specifications() ) {
					push @data, $Sensor->name(), $Spec->name(), $Spec->value();
				} # end foreach
			} # end foreach
			misc::export_csv( $r, $log, \%variable, 'SensorSpecifications.csv', \@header, \@data );
		} elsif ( $param{action} eq 'Import Specifications' ) {
			my $error = '';
			if ( $param{fileImport} ) {
				my $upload = $r->upload( 'fileImport' );
				my $io = $upload->io();
				$_ = <$io>;

				my $csv = Text::CSV_XS->new();
				my $ac = sql::start_transaction( $dbh );
				my %sensors = map { $_->name(), $_ } EnviroTrack::Sensor->find();
				# Clear Specifications
				foreach my $P ( keys %sensors ) {
					$sensors{$P}{Specifications} = ();
				} # end foreach
				
				while ( <$io> ) {
					my $status = $csv->parse($_);
					my ( $sensor, $name, $value ) = misc::trim( $csv->fields() );
					next if ! $sensor;
					$sensors{$sensor}{Specifications}{$name} = $value;
				} # end while

				foreach my $P ( keys %sensors ) {
					$error .= $sensors{$P}->save();
				} # end foreach
				sql::end_transaction( $dbh, $ac );
			} # end if
		} # end if
	} # end if param{action}
	$variable{Sensor} = $Sensor;
} # end sub edit

sub search {
	_search();
	if ( ( ! $session{'/sensor/search.html?lastupdated'} ) or ( time - $session{'/sensor/search.html?lastupdated'} ) > ( 12*60*60 ) ) {
		ssi::setup_date_select( '/sensor/search.html', 'starting_on_start', 0 );
		ssi::setup_date_select( '/sensor/search.html', 'starting_on_end', '' );
	} # end if
} # end sub search

sub _search {
	if ( ! $param{action} ) {
		ssi::save_params( '/sensor/search.html', ( 
				'starting_on_start_year','starting_on_start_month','starting_on_start_day',
				'starting_on_end_year','starting_on_end_month','starting_on_end_day',
				'user_id', 'category_id', 'country_id', 'state_id', 'city_id' ) );
	} # end if
} # end sub _history

sub _input {
	my $Input = new EnviroTrack::Sensor_Input( $param{id} );
	if ( $param{action} eq 'add' ) {
		foreach my $k ( 'sensor_id' ) {
			$$Input{$k} = $param{$k};
		} # end foreach
		$Input->save();
		$variable{Input} = $Input;
	} elsif ( $param{action} eq 'copy' ) {
		my $NewInput = $Input->copy();
		delete $param{id};
		$variable{error} .= $NewInput->save(\%param);
		$variable{Input} = $NewInput;
		$param{id} = $NewInput->id();
		
	} elsif ( $param{action} eq 'save' ) {
		my @changes = $Input->changes( \%param );
		$variable{error} = $Input->save(\%param);
		if ( ! $variable{error} ) {
			my $Sensor = $Input->Sensor();
			(new openprint::Log())->save({ Object=>$Sensor, action=>'Save',
				note=>$$Input{name} . ' ' . join('<br/>', @changes ) });
		} # end if
		$variable{Input} = $Input;
	} elsif ( $param{action} eq 'delete' ) {
		$Input->delete();
		$variable{PageContent} = ' ';
	} # end if
} # end sub _input
1;
__END__
