package openprint::employee_iso;
use openprint;
use vars qw( %variable %session %param %config $log $dbh $r );
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*r = \$openprint::r;

require openprint::CAR;
require openprint::CAR_Reason;
require openprint::CAR_Area;
require openprint::PAR;
require openprint::MAR;

use strict;
use warnings;

sub mars {
	if ( $param{btnFunction} ) {
		if ( $param{btnFunction} eq 'Delete' ) {
			foreach my $MAR ( openprint::MAR->find(
						( ref $param{mars} eq 'ARRAY' ? ( id=>$param{mars} ) : ( id=>$param{mars} ) )
						) ) {
				$variable{error} .= $MAR->delete();
			} # end foreach MAR
		} elsif ( $param{btnFunction} eq 'Download in CSV Format' ) {
			my @header = (
					'Issued To','Issued On','Issued By','Reply By',
					'Equipment','Problem','Cause','Action','Effectiveness',
					'Part2 Recipient', 'Part2 Signed On',
					'Part3 Recipient', 'Part3 Signed On',
					'Part4 QS Mgt Rep/Designate', 'Part4 Signed On',
					);
			my @data;
			my %params = (
				ssi::date_filter( 'issued_on_start', 'issued_on >=', \%param ),
				ssi::date_filter( 'issued_on_end', 'issued_on <=', \%param ),
			);
			my @MARs = openprint::MAR->find(%params);
			if ( @MARs ) {
				openprint::Company->find(id=>[ map { $$_{company_id} ? $$_{company_id} : () } @MARs ]);
				openprint::User->find(id=>[ map { 
						( $$_{issued_to_id} ? $$_{issued_to_id} : () ),
						( $$_{issued_by_id} ? $$_{issued_by_id} : () ),
						( $$_{part2_user_id} ? $$_{part2_user_id} : () ),
						( $$_{part3_user_id} ? $$_{part3_user_id} : () ),
						( $$_{part4_user_id} ? $$_{part4_user_id} : () ),
						} @MARs ]);
			}
			foreach my $MAR ( @MARs ) {
				push @data, (
						new openprint::User($MAR->issued_to_id() )->name(),
						$MAR->issued_on(),
						new openprint::User($MAR->issued_by_id() )->name(),
						$MAR->reply_by(),
						( $MAR->presses() ? join( ',', map { new openprint::Equipment($_)->name() } split(';', $MAR->presses()) ) : '' ),
						$MAR->problem(),
						$MAR->cause(),
						$MAR->action(),
						$MAR->effectiveness(),
						new openprint::User($MAR->part2_user_id())->name(),
						$MAR->part2_signed_on(),
						new openprint::User($MAR->part3_user_id())->name(),
						$MAR->part3_signed_on(),
						new openprint::User($MAR->part4_user_id())->name(),
						$MAR->part4_signed_on(),
						);
			} # end foreach MAR
			
			misc::export_csv( $r, $log, \%variable, 'MARS.csv', \@header, \@data );
		} # end if
	} # end if btnFunction
	_mars();
	ssi::setup_date_select( '/employee/iso/mars.html', 'issued_on_start', -30 );
	ssi::setup_date_select( '/employee/iso/mars.html', 'issued_on_end', '' );
	$session{'/employee/iso/mars.html?status'} = '' if ! exists $session{'/employee/iso/mars.html?status'};
} # end sub mars

sub _mars {
	ssi::save_params( '/employee/iso/mars.html', ( 
				'issued_on_start_year','issued_on_start_month','issued_on_start_day',
				'issued_on_end_year','issued_on_end_month','issued_on_end_day',
				'status','equipment_id' ) );
} # end sub _mars

sub mar {
	$variable{MAR} = new openprint::MAR( $param{mar_id} );
	if ( $param{action} eq 'Send' ) {
		$variable{MAR}->send_notifications();
	} # end if
} # end sub view_mar

sub _mar_view_part1 {
	my $MAR = $variable{MAR} = new openprint::MAR( $param{mar_id} );
	if ( $param{btnFunction} eq 'Save' ) {
		$param{issued_on} = sprintf('%.4d-%.2d-%.2d', @param{'issued_on_year','issued_on_month','issued_on_day'} );
		$param{reply_by} = sprintf('%.4d-%.2d-%.2d', @param{'reply_by_year','reply_by_month','reply_by_day'} ) if $param{reply_by_day};
		my $send_assignee_notification = 0;

		if ( $param{issued_to_id} and ! $MAR->issued_to_id() ) {
			$send_assignee_notification = 1;
		} # end if issued_to
		# if a reprint is requested, but if the approval is already given, then we are the Approver, so don't bother.

		my @changes = $MAR->changes(\%param);
		if ( @changes ) {
			$variable{error} .= $MAR->save( \%param );
			if ( ! $variable{error} ) {
				(new openprint::Log())->save({action=>'Edit', Object=>$MAR, note=>join('<br/>', @changes)});
				$MAR->send_notifications();
				if ( $send_assignee_notification ) {
					$MAR->send_assignee_notification();
				} # end if
			} # end if no errors
		} # end if changes
	} # end if btnFunction is Save
} # end sub _mar_view_part1

sub _mar_view_part2 {
	my $MAR = $variable{MAR} = new openprint::MAR( $param{mar_id} );
	if ( $param{btnFunction} eq 'Save' ) {
		$param{part2_signed_on} = sprintf('%.4d-%.2d-%.2d', @param{'part2_signed_on_year','part2_signed_on_month','part2_signed_on_day'} );
		my @changes = $MAR->changes(\%param);
		if ( @changes ) {
			$variable{error} .= $MAR->save(\%param);
			if ( ! $variable{error} ) {
				(new openprint::Log())->save({action=>'Edit', Object=>$MAR, note=>join('<br/>', @changes)});
				$MAR->send_changed_notification();
			} # end if
		} # end if changes
	} # end if
} # end sub _mar_view_part2

sub _mar_view_part3 {
	my $MAR = $variable{MAR} = new openprint::MAR( $param{mar_id} );
	if ( $param{btnFunction} eq 'Save' ) {
		$param{part3_signed_on} = sprintf('%.4d-%.2d-%.2d', @param{'part3_signed_on_year','part3_signed_on_month','part3_signed_on_day'} );
		my @changes = $MAR->changes(\%param);
		if ( @changes ) {
			$variable{error} .= $MAR->save( \%param );
			if ( ! $variable{error} ) {
				(new openprint::Log())->save({action=>'Edit', Object=>$MAR, note=>join('<br/>', @changes)});
				$MAR->send_changed_notification();
			} # end if
		} # end if changes
	} # end if
} # end sub _mar_view_part3

sub _mar_view_part4 {
	my $MAR = $variable{MAR} = new openprint::MAR( $param{mar_id} );
	if ( $param{btnFunction} eq 'Save' ) {
		$param{part4_signed_on} = sprintf('%.4d-%.2d-%.2d', @param{'part4_signed_on_year','part4_signed_on_month','part4_signed_on_day'} );
		$variable{error} .= $MAR->save( \%param );
		if ( ! $variable{error} ) {
			$MAR->send_changed_notification();
		} # end if
	} # end if
} # end sub _mar_view_part4

sub _mar_edit_part1 {
	$variable{MAR} = new openprint::MAR( $param{mar_id} );
}
sub _mar_edit_part2 {
	$variable{MAR} = new openprint::MAR( $param{mar_id} );
}
sub _mar_edit_part3 {
	$variable{MAR} = new openprint::MAR( $param{mar_id} );
}
sub _mar_edit_part4 {
	$variable{MAR} = new openprint::MAR( $param{mar_id} );
}

### CARS SECTIONS BEGINS HERE
sub cars {
	$variable{error} = '';

	if ( $param{btnFunction} ) {
		if ( $param{btnFunction} eq 'Delete' ) {
			foreach my $CAR ( openprint::CAR->find(
						( ref $param{cars} eq 'ARRAY' ? ( id=>$param{cars} ) : ( id=>$param{cars} ) )
						) ) {
				$variable{error} .= $CAR->delete();
			} # end foreach CAR
		} elsif ( $param{btnFunction} eq 'Download in CSV Format' ) {
			my @header = (
					'Issued To','Issued On','Issued By','Reply By',
					'Docket','Customer','Identified By','Printed On','Presses',
					'Area','Reason','Problem','Cause','Action','Effectiveness',
					'Part2 Recipient', 'Part2 Signed On',
					'Part3 Recipient', 'Part3 Signed On',
					'Part4 QS Mgt Rep/Designate', 'Part4 Signed On',
					'Reprint Requested','Reprint Approved','Reprint Charge','Reprint Quantity',
					'Reprint Value', 'Reprint On','Reprint Approved By', 'Approved On','Artwork' );
			my @data;
			my %params = (
				ssi::date_filter( 'issued_on_start', 'issued_on >=', \%param ),
				ssi::date_filter( 'issued_on_end', 'issued_on <=', \%param ),
			);
			my @CARs = openprint::CAR->find(%params);
			if ( @CARs ) {
				openprint::Company->find(id=>[ map { $$_{company_id} } @CARs ]);
				openprint::User->find(id=>[ map { 
						( $$_{issued_to_id} ? $$_{issued_to_id} : () ),
						( $$_{issued_by_id} ? $$_{issued_by_id} : () ),
						( $$_{part2_user_id} ? $$_{part2_user_id} : () ),
						( $$_{part3_user_id} ? $$_{part3_user_id} : () ),
						( $$_{part4_user_id} ? $$_{part4_user_id} : () ),
						( $$_{approved_by_id} ? $$_{approved_by_id} : () ),
						} @CARs ]);
			}
			
			foreach my $CAR ( @CARs ) {
				push @data, (
						new openprint::User($CAR->issued_to_id() )->name(),
						$CAR->issued_on(),
						new openprint::User($CAR->issued_by_id() )->name(),
						$CAR->reply_by(),
						$CAR->docket(),
						$CAR->Company()->name(),
						$CAR->identified_by(),
						$CAR->printed_on(),
						( $CAR->presses() ? join( ',', map { new openprint::Equipment($_)->name() } split(';', $CAR->presses()) ) : '' ),
						$CAR->Area()->name(),
						$CAR->Reason()->name(),
						$CAR->problem(),
						$CAR->cause(),
						$CAR->action(),
						$CAR->effectiveness(),
						new openprint::User($CAR->part2_user_id())->name(),
						$CAR->part2_signed_on(),
						new openprint::User($CAR->part3_user_id())->name(),
						$CAR->part3_signed_on(),
						new openprint::User($CAR->part4_user_id())->name(),
						$CAR->part4_signed_on(),
						$CAR->reprint(),
						$CAR->reprint_approval(),
						$CAR->reprint_charge(),
						$CAR->reprint_quantity(),
						$CAR->reprint_value(),
						$CAR->reprint_on(),
						new openprint::User( $CAR->approved_by_id() )->name(),
						$CAR->approved_on(),
						$CAR->artwork(),
						);
			} # end foreach CAR
			
			misc::export_csv( $r, $log, \%variable, 'CARS.csv', \@header, \@data );
		} # end if
	} # end if btnFunction
	_car_results();
	ssi::setup_date_select( '/employee/iso/cars.html', 'issued_on_start', -30 );
	ssi::setup_date_select( '/employee/iso/cars.html', 'issued_on_end', '' );
	$session{'/employee/iso/cars.html?status'} = 'Open' if ! exists $session{'/employee/iso/cars.html?status'};
} # end sub cars

sub _car_results {
	ssi::save_params( '/employee/iso/cars.html', ( 
				'issued_on_start_year','issued_on_start_month','issued_on_start_day',
				'issued_on_end_year','issued_on_end_month','issued_on_end_day',
				'status','docket' ) );
} # end sub _car_results

sub car {
	$variable{error} = '';

	my $CAR = $variable{CAR} = new openprint::CAR( $param{car_id} );
	if ( $param{action} ) {
		if ( $param{action} eq 'Send' ) {
			$variable{CAR}->send_notifications();
		}
	}
	if ( $param{btnFunction} ) {

		if ( $param{btnFunction} eq 'Save' ) {
			foreach my $date_field(
					'part2_signed_on',
					'part3_signed_on',
					'part4_signed_on',
					'issued_on', 'reprint_on', 'printed_on', 'approved_on','reply_by' ) {
				$param{$date_field} = sprintf('%.4d-%.2d-%.2d', @param{map{ $date_field.'_'.$_} ( 'year','month','day')} ) if $param{$date_field.'_year'};
			}
			if ($param{reprint_approval} and ($param{reprint_approval} eq 'Yes')) {
			} else {
				$param{approved_on} = undef;
			}
			$param{presses} = (ref $param{presses} eq 'ARRAY' ? join(';', @{$param{presses}} ) : $param{presses}) if exists $param{presses};

			my $send_assignee_notification = 0;
			my $send_reprint_request_notification = 0;
			my $send_reprint_approval_notification = 0;

			if ( $param{area_id} and ( ! $param{issued_to_id} ) and ( ! $CAR->issued_to_id() ) ) {
# Auto assignation
				my $Area = new openprint::CAR_Area( $param{area_id} );
				if ( $Area->assignee_id() ) {
					$param{issued_to_id} = $Area->assignee_id();
				} elsif ( $param{docket} ) {
# Assign to the CSR for the docket
					my $Order = openprint::Order->find_one(docket=>$param{docket} );
					if ( $Order ) {
						$param{issued_to_id} = $Order->salesrep_id();
					} # end if
				} # end if
			} # end if

			if ( $param{issued_to_id} and ! $CAR->issued_to_id() ) {
				$send_assignee_notification = 1;
			} # end if issued_to

# if a reprint is requested, but if the approval is already given, then we are the Approver, so don't bother.
			if ( $param{reprint} and ($param{reprint} eq 'Yes') ) {
				if ( ( (!$CAR->reprint()) or ($CAR->reprint() ne 'Yes')) and !$param{reprint_approval} ) {
					$send_reprint_request_notification = 1;
				} elsif ( $param{reprint_approval} and ($param{reprint_approval} eq 'Yes') and ($param{reprint_approval} ne $variable{CAR}->reprint_approval()) ) {
					$send_reprint_approval_notification = 1;
				} # end if reprint
			} # end if reprint

			my @changes = $CAR->changes(\%param);
			if ( @changes ) {	
				$variable{error} .= $CAR->save(\%param);

				if ( ! $variable{error} ) {
					(new openprint::Log())->save({action=>'Edit', Object=>$CAR, note=>join('<br/>', @changes)});
					if ( ( ! $param{car_id} ) and ! $send_reprint_request_notification ) {
# Send out notifications
						$CAR->send_notifications();
					} else {
						$CAR->send_changed_notification();
					} # end if

					if ( $send_reprint_request_notification ) {
						$CAR->send_reprint_request_notification();
					} # end if
					if ( $send_assignee_notification ) {
						$CAR->send_assignee_notification();
					} # end if
					if ( $send_reprint_approval_notification ) {
						$CAR->send_reprint_approval_notification();
					} # end if
				} # end if no errors
				$variable{ExternalRedirect} = '/employee/iso/car.html?car_id='.$CAR->id();
			} # end if changes

		} # end if btnFunction is Save
	} # end if btnFunction
} # end sub car

sub _car_view_part1 {
	my $CAR = $variable{CAR} = new openprint::CAR( $param{car_id} );
} # end sub _car_view_part1

sub _car_view_part2 {
	my $CAR = $variable{CAR} = new openprint::CAR( $param{car_id} );
} # end sub _car_view_part2

sub _car_view_part3 {
	my $CAR = $variable{CAR} = new openprint::CAR( $param{car_id} );
} # end sub _car_view_part3

sub _car_view_part4 {
	my $CAR = $variable{CAR} = new openprint::CAR( $param{car_id} );
} # end sub _car_view_part4

sub _car_edit_part1 {
	$variable{CAR} = new openprint::CAR( $param{car_id} );
}
sub _car_edit_part2 {
	$variable{CAR} = new openprint::CAR( $param{car_id} );
}
sub _car_edit_part3 {
	$variable{CAR} = new openprint::CAR( $param{car_id} );
}
sub _car_edit_part4 {
	$variable{CAR} = new openprint::CAR( $param{car_id} );
}

sub pars {
	if ( $param{btnFunction} ) {
		if ( $param{btnFunction} eq 'Delete' ) {
			foreach my $PAR ( openprint::PAR->find(
						( ref $param{pars} eq 'ARRAY' ? ( id=>$param{pars} ) : ( id=>$param{pars} ) )
						) ) {
				$variable{error} .= $PAR->delete();
			} # end foreach PAR
		} elsif ( $param{btnFunction} eq 'Download in CSV Format' ) {
			my @header = ('Issued To','Issued On','Issued By','Reply By', 'Area','Reason','Problem','Cause','Action','Effectiveness', 
					'Part1 Recipient', 'Part1 Signed On', 'Part2 Recipient', 'Part2 Signed On', 'Part3 Recipient', 'Part3 Signed On', 'Part4 QS Mgt Rep/Designate', 'Part4 Signed On' );
			my @data;
			my %params = (
					ssi::date_filter( 'issued_on_start', 'issued_on >=', \%param ),
					ssi::date_filter( 'issued_on_end', 'issued_on <=', \%param ),
					);
			my @PARs = openprint::PAR->find(%params);
			if ( @PARs ) {
				openprint::Company->find(id=>[ map { $$_{company_id} } @PARs ]);
				openprint::User->find(id=>[ map { 
						( $$_{issued_to_id} ? $$_{issued_to_id} : () ),
						( $$_{issued_by_id} ? $$_{issued_by_id} : () ),
						( $$_{part1_user_id} ? $$_{part1_user_id} : () ),
						( $$_{part2_user_id} ? $$_{part2_user_id} : () ),
						( $$_{part3_user_id} ? $$_{part3_user_id} : () ),
						( $$_{part4_user_id} ? $$_{part4_user_id} : () ),
						} @PARs ]);
			}
			foreach my $PAR ( @PARs ) {
				push @data, (
						new openprint::User($PAR->issued_to_id() )->name(),
						$PAR->issued_on(),
						new openprint::User($PAR->issued_by_id() )->name(),
						$PAR->reply_by(),
						$PAR->Area()->name(),
						$PAR->Reason()->name(),
						$PAR->problem(),
						$PAR->cause(),
						$PAR->action(),
						$PAR->effectiveness(),
						new openprint::User($PAR->part1_user_id())->name(),
						$PAR->part1_signed_on(),
						new openprint::User($PAR->part2_user_id())->name(),
						$PAR->part2_signed_on(),
						new openprint::User($PAR->part3_user_id())->name(),
						$PAR->part3_signed_on(),
						new openprint::User($PAR->part4_user_id())->name(),
						$PAR->part4_signed_on(),
						);

			} # end foreach CAR

			misc::export_csv( $r, $log, \%variable, 'PARS.csv', \@header, \@data );
		} # end if
	} # end if btnFunction
	ssi::setup_date_select( '/employee/iso/pars.html', 'issued_on_start', -365 );
	ssi::setup_date_select( '/employee/iso/pars.html', 'issued_on_end', '' );
	_par_results();
} # end sub pars

sub _par_results {
	ssi::save_params( '/employee/iso/pars.html', ( 
				'issued_on_start_year','issued_on_start_month','issued_on_start_day',
				'issued_on_end_year','issued_on_end_month','issued_on_end_day', 'status',
				'docket',
				) );
} # end sub _par_results

sub par {
	$variable{PAR} = new openprint::PAR( $param{par_id} );
} # end sub view_par

sub _par_view_part1 {
	$variable{PAR} = new openprint::PAR( $param{par_id} );
	if ( $param{btnFunction} eq 'Save' ) {
		$param{issued_on} = sprintf('%.4d-%.2d-%.2d', @param{'issued_on_year','issued_on_month','issued_on_day'} );
		$param{reply_by} = sprintf('%.4d-%.2d-%.2d', @param{'reply_by_year','reply_by_month','reply_by_day'} );
		$param{part1_signed_on} = sprintf('%.4d-%.2d-%.2d', @param{'part1_signed_on_year','part1_signed_on_month','part1_signed_on_day'} );
		$variable{error} .= $variable{PAR}->save( \%param );
		if ( $variable{PAR}->id() and ! $param{par_id} ) {
			# Send out notifications
			$variable{PAR}->send_notifications();
		} # end if
	} # end if
} # end sub _par_view_part1

sub _par_view_part2 {
	$variable{PAR} = new openprint::PAR( $param{par_id} );
	if ( $param{btnFunction} eq 'Save' ) {
		$param{part2_signed_on} = sprintf('%.4d-%.2d-%.2d', @param{'part2_signed_on_year','part2_signed_on_month','part2_signed_on_day'} );
		$param{cause} =~ s/<br\/>/\n/g;
		$variable{error} .= $variable{PAR}->save( \%param );
	} # end if
} # end sub _par_view_part2
sub _par_view_part3 {
	$variable{PAR} = new openprint::PAR( $param{par_id} );
	if ( $param{btnFunction} eq 'Save' ) {
		$param{part3_signed_on} = sprintf('%.4d-%.2d-%.2d', @param{'part3_signed_on_year','part3_signed_on_month','part3_signed_on_day'} );
		$variable{error} .= $variable{PAR}->save( \%param );
	} # end if
} # end sub _par_view_part3

sub _par_view_part4 {
	$variable{PAR} = new openprint::PAR( $param{par_id} );
	if ( $param{btnFunction} eq 'Save' ) {
		$param{part4_signed_on} = sprintf('%.4d-%.2d-%.2d', @param{'part4_signed_on_year','part4_signed_on_month','part4_signed_on_day'} );
		$variable{error} .= $variable{PAR}->save( \%param );
	} # end if
} # end sub _par_view_part4

sub _par_edit_part1 {
	$variable{PAR} = new openprint::PAR( $param{par_id} );
}
sub _par_edit_part2 {
	$variable{PAR} = new openprint::PAR( $param{par_id} );
}
sub _par_edit_part3 {
	$variable{PAR} = new openprint::PAR( $param{par_id} );
}
sub _par_edit_part4 {
	$variable{PAR} = new openprint::PAR( $param{par_id} );
}

sub _select_customer_from_docket {
	$param{docket} =~ s/\D//g;
} # end sub _select_customer_from_docket

sub _select_assignee_from_area {
} # end sub _select_assignee_from_area

1;
__END__
