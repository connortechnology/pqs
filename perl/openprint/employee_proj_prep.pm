package openprint::employee_proj_prep;
use strict;

use openprint ();

require openprint::Project;
require openprint::order;
require openprint::service;
require openprint::Equipment;
require openprint::employee_schedule;
require openprint::press_schedule;

require openprint::employee_production;
require openprint::employee_project;

require sql;
require openprint::ServiceType_Category;
require openprint::SignatureCapture;
require openprint::File;
require openprint::User_Notification;
require openprint::Operator_Role;
require openprint::Project_Service_Operator;
require openprint::CIP3_PPF;


use vars qw( $r $log $dbh %variable %param %session %config );
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;

sub init {
	openprint::employee_production::load_press_completion( $log, $dbh, \%variable, $variable{ProjectIndex} );
}

sub proofs {
	if ( $param{action} eq 'SendPPF' ) {
		my $Project = new openprint::Project( $param{ProjectIndex} );
		require openprint::CIP3_PPF;
		my $PPF = new openprint::CIP3_PPF( $param{ppf_id} );

		my $Equipment;
		foreach my $sig_id ( $Project->signatures() ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $sig_id );
			if ( $$sig_specs{SignatureIndex} == $$PPF{signature} ) {
				$log->debug("Found sig");
				my @Equipment = openprint::Equipment->find('strid'=>$$sig_specs{UsePress} ? $$sig_specs{UsePress} : $$sig_specs{'ddmPress'.$Project->ordered_quantity_index()} );
				if ( @Equipment ) {
					$Equipment = $Equipment[0];
					last;
				}
			} # end if
		} # end foreach
		if ( ! $Equipment ) {
			$log->debug("Looking it up from Schedule");
			my @rows = openprint::press_schedule->find('project_id'=>$param{ProjectIndex},'service_id'=>$param{ServiceIndex});
			if ( @rows == 1 ) {
				$Equipment = new openprint::Equipment( $rows[0]{equipment_id} );
			}
		} # end if
		if ( ! $Equipment ) {
			$log->error("Unable to load equipment.  No PPF for you for signature $$PPF{signature}.");
		} else {
			$PPF->send_ppf( $Equipment );
		} # end if
	} # end if
} # end sub proofs

sub _proofs_signatures {
	$variable{ProjectIndex} = $param{ProjectIndex};
	my $Project = $variable{Project} = new openprint::Project( $param{ProjectIndex} );

	if ( $param{btnFunction} ) {
    if ( $param{btnFunction} eq 'Delete Proofs' ) {
      my $proof_specs = openprint::service::get_specs_ref( $Project, $param{ServiceIndex} );
      foreach my $sid ( $Project->signatures() ) {
        my $sig_specs = openprint::service::get_specs_ref( $Project, $sid );
        foreach my $key ( keys %$proof_specs ) {
          if ( $key =~ /txtProofQuantity-$$sig_specs{SignatureIndex}-(\d*)/ ) {
            my $proof_index = $1;
            if ( $param{"chkDelete-$$sig_specs{SignatureIndex}-$proof_index"} ) {
              openprint::Estimating::Proofs::delete_proof( $log, $dbh, @param{'ProjectIndex','ServiceIndex'}, $$sig_specs{SignatureIndex}, $proof_index );
            } # end if
          } # end if
        } # end foreach  key
      } # end foreach $sid
    } elsif ( $param{btnFunction} eq 'Add Proof' ) {
      $variable{ServiceIndex} = $param{ServiceIndex};

      my $custom_line;
      foreach my $sid ( $Project->signatures() ) {
        my $sig_specs = openprint::service::get_specs_ref( $Project, $sid );

        if ( $param{"UsePress-$sid"} ne $$sig_specs{UsePress} ) {
          openprint::service::insert_service_spec( $log, $dbh, $param{ProjectIndex}, $sid, 'UsePress', $param{"UsePress-$sid"} );
          if ( my @Equipment = openprint::Equipment->find('strid'=>$param{"UsePress-$sid"}) ) {
            $variable{information} .= qq`Changed press for Signature $$sig_specs{SignatureIndex} to $param{"UsePress-$sid"}<br/>`;
          } else {
            $variable{error} .= 'Error: invalid press?';
          } # end if
        } # end if
      } # end foreach

      my %proof_specs = openprint::service::get_specifications_pairs( $log, $dbh, @param{'ProjectIndex','ServiceIndex'} );
      openprint::Estimating::Proofs::calc( $log, $dbh, \%variable, @param{'ProjectIndex','ServiceIndex'}, \%proof_specs );

      my $qty_index = $Project->ordered_quantity_index();
      foreach my $sid ( $Project->signatures() ) {
        my $sig_specs = openprint::service::get_specs_ref( $param{ProjectIndex}, $sid );
        if ( $param{"txtProofQuantity-$$sig_specs{SignatureIndex}"} ) {
          my $proof_index = 0;
          foreach my $key ( keys %proof_specs ) {
            if ( $key =~ /txtProofQuantity-$$sig_specs{SignatureIndex}-(\d*)-$qty_index/ ) {
              if ( $1 > $proof_index ) {
                $proof_index = $1;
              } # end if
            } # end if
          } # end foreach  key
          $proof_index = 3 if ( $proof_index < 3 );
          $proof_index += 1;
          $param{"txtProofQuantity-$$sig_specs{SignatureIndex}"} =~ s/\D//g;
          $param{"txtProofHeight-$$sig_specs{SignatureIndex}"} =~ s/[^\d\.]//g;
$param{"txtProofWidth-$$sig_specs{SignatureIndex}"} =~ s/[^\d\.]//g;

          $proof_specs{"txtProofIndex-$$sig_specs{SignatureIndex}-$proof_index-$qty_index"} = $proof_index;
          $proof_specs{"txtProofQuantity-$$sig_specs{SignatureIndex}-$proof_index-$qty_index"} = $param{"txtProofQuantity-$$sig_specs{SignatureIndex}"};
          $proof_specs{"txtProofWidth-$$sig_specs{SignatureIndex}-$proof_index-$qty_index"} = $param{"txtProofWidth-$$sig_specs{SignatureIndex}"};
          $proof_specs{"txtProofHeight-$$sig_specs{SignatureIndex}-$proof_index-$qty_index"} = $param{"txtProofHeight-$$sig_specs{SignatureIndex}"};
          $proof_specs{"ddmProofType-$$sig_specs{SignatureIndex}-$proof_index-$qty_index"} = $param{"ddmProofType-$$sig_specs{SignatureIndex}"};
          $proof_specs{"chkOverride-$$sig_specs{SignatureIndex}-$proof_index-$qty_index"} = 'Y';

          $variable{information} .= qq`Added $param{"txtProofQuantity-$$sig_specs{SignatureIndex}"} $param{"ddmProofType-$$sig_specs{SignatureIndex}"} to Signature $$sig_specs{SignatureIndex}<br/>`;

          $Project->add_to_log( @session{'company_id','user_id'}, sprintf( 'Added Proof %d %sx%s %s for signature %s', @param{"txtProofQuantity-$$sig_specs{SignatureIndex}", "txtProofWidth-$$sig_specs{SignatureIndex}", "txtProofHeight-$$sig_specs{SignatureIndex}", "ddmProofType-$$sig_specs{SignatureIndex}"}, $$sig_specs{SignatureIndex}) );

          $custom_line .= sprintf( '%d Additional %sx%s %s Proof', @param{"txtProofQuantity-$$sig_specs{SignatureIndex}", "txtProofWidth-$$sig_specs{SignatureIndex}", "txtProofHeight-$$sig_specs{SignatureIndex}", "ddmProofType-$$sig_specs{SignatureIndex}"});

        } # end if
      } # end foreach sid

      # If we added any proofs
      if ( $custom_line ) {
        $Project->status( 'Waiting For Customer Approval' );
        $Project->save();
        $Project->Order()->status( 'Waiting For Customer Approval' );

        my @prices = @proof_specs{'txtPrice1','txtPrice2','txtPrice3'};
        openprint::Estimating::Proofs::calc( $log, $dbh, \%variable, @param{'ProjectIndex','ServiceIndex'}, \%proof_specs );

        # Now do the abominable thing and add a custom line item for it too...

        if ( my $ServiceType = openprint::ServiceType->find_one(name=>'CustomService') ) {
                 $Project->add_service( $ServiceType, { ServiceName => $custom_line,
                          txtPrice1 => $proof_specs{txtPrice1}-$prices[0],
                          txtPrice2 => $proof_specs{txtPrice2}-$prices[1],
                          txtPrice3 => $proof_specs{txtPrice3}-$prices[2],
              }, { status => 'Waiting For Customer Approval' }
                          );

        } else {
          $variable{ErrorMessage}.='Error adding proof: Unable to find service CustomService';
        } # end if
      } # end if

    } # end if btnFunction value
  } # end if btnFunction
} # end sub _proofs_signatures

1;
__END__
