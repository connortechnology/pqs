# Copyright (C) 2007 Isaac Connor <isaac@connortechnology.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA
use strict;
use warnings;

package openprint::Estimating::Proofs;
use POSIX qw( ceil );
require openprint;

use vars qw( $log $dbh );
*log = \$openprint::log;
*dbh = \$openprint::dbh;

require sql;
require openprint::Project;
require openprint::service;
require openprint::Estimating::Printing;
use Data::Dumper;

use constant DEBUG => 1;
use constant LAYOUT_PROOF => 1;
use constant COLOUR_PROOF => 2;
use constant PRESS_PROOF => 3;
use constant FOLDING_PROOF => 4;
use constant PDF_PROOF => 5;

my %ServicePrices = (
  'ColourLaser' => { 
    range_units =>[ 'square inches', 'proof quantity', 'pages' ],
    units=>['each','per proof', 'per square inch', 'per square foot'],
  },
  'DigitalDylux' => {
    range_units =>[ 'square inches', 'proof quantity', 'pages' ],
    units=>['each','per proof', 'per square inch', 'per square foot'],
  },
  '.*Proof' => {
    range_units =>[ 'square inches', 'proof quantity', 'pages' ],
    units=>['each','per proof', 'per square inch', 'per square foot'],
  },
);
my %Specifications = (
);

sub ServicePriceConfiguration {
  my $name = shift;
  return $ServicePrices{$name} if $ServicePrices{$name};
  foreach my $key (keys %ServicePrices) {
    $log->debug("$key $name");
    return $ServicePrices{$key} if ($name =~ /$key/i);
    $log->debug("$key $name");
  }
  return undef;
}
sub SpecificationConfiguration {
  return $Specifications{shift};
}

my %ProofServices;

my @variables = (
  'CustomProofSpecs',
  'RequireColourProofs',
  'RequireLayoutProofs',
  'RequireFoldingProofs',
  'RequirePressProofs',
  'RequirePDFProofs',
  'alert',
);

sub variables {
	my ( $p_id, $s_id, $old_specs, $specs ) = @_;

	my $Project = new openprint::Project( $p_id );
	my @v = @variables;
	foreach my $qty_index ( $Project->quantity_indexes() ) {
		push @v, 'Markup'.$qty_index, 'txtPrice'.$qty_index, 'OverridePrice'.$qty_index;
	} # end foreach qty_index

	foreach my $ss_id ( $Project->signatures() ) {
    my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
    my $Imposition = new openprint::Imposition();
    $Imposition->load($sig_specs, 1, $Project);
    $$Imposition{service_id} = $ss_id;
    my $form = $Imposition->form();
		foreach my $key ( keys %{$specs} ) {
			if ( $key =~ /^txtProofIndex\-$form\-(\d+)\-(\d+)$/ ) {
				my ( $proof_index, $qty_index ) = ( $1, $2 );

				push @v, map { join('-', $_, $form, $proof_index, $qty_index) }
				(
				 'txtProofWidth',
				 'txtProofHeight',
				 'txtProofQuantity',
				 'ddmProofType',
				 'txtProofUnitPrice',
				 'txtProofIndex',
				 'OverridePrice',
				 'OverrideSize',
				);
			} # end if
		} # end foreach key
	} # end foreach signature
	return @v;
} # end sub variables

sub outputs {
	my ( $p_id, $s_id, $specs ) = @_;

	my $Project = new openprint::Project( $p_id );
	my @v;
	foreach my $qty_index ( $Project->quantity_indexes() ) {
		push @v, 'txtPrice'.$qty_index, "hdnBreakdown$qty_index";
	} # end foreach qty_index

	foreach my $ss_id ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
    my $Imposition = new openprint::Imposition();
    $Imposition->load($sig_specs, 1, $Project);
    $$Imposition{service_id} = $ss_id;
    my $form = $Imposition->form();
		foreach my $key ( keys %{$specs} ) {
			if ( $key =~ /^txtProofIndex\-$form\-(\d+)\-(\d+)$/ ) {
				my ( $proof_index, $qty_index ) = ( $1, $2 );

				push @v,	(
						"txtProofWidth-$form-$proof_index-$qty_index",
						"txtProofHeight-$form-$proof_index-$qty_index", 
						"txtProofQuantity-$form-$proof_index-$qty_index",
						"ddmProofType-$form-$proof_index-$qty_index",
						"txtProofUnitPrice-$form-$proof_index-$qty_index",
						"txtProofIndex-$form-$proof_index-$qty_index",
            #"Override-$form-$proof_index-$qty_index",
						);
			} # end if
		} # end foreach key
	} # end foreach signature
	return @v;
} # end sub outputs

sub no_outputs {
} # end sub no_outputs

sub get_indexes {
	my ( $specs, $qty_index, $indexes, $types ) = @_;
	foreach my $key ( keys %{$specs} ) {
		if ( $key =~ /^txtProofIndex\-(\d+)\-(\d+)\-$qty_index$/ ) {
      $openprint::log->debug($key);
			$$indexes{$1}[$$specs{$key}] = $$specs{$key};
			push @{$$types{$1}}, $$specs{"ddmProofType-$1-$2-$qty_index"};
		} # end if
	} # end foreach
if ( DEBUG ) {
$openprint::log->debug(Data::Dumper::Dumper($indexes));
}
} # end sub get_indexes

sub necessary {
  my ($project) = @_;
  if (@_ == 4) {
    my ($log, $dbh, $pid, $service_type) = @_;
    $project = new openprint::Project($pid);
  }

  my $type = $project->press_type();

  # Inkjets are often proofers, and digital creates it's own.
  return 0 if $type eq 'inkjetprinter' || $type eq 'digital';

  my $project_type = $project->type();
  return 0 if $project_type eq 'InventoryCheckOut';
  return 0 if $project_type eq 'NoPrint';

  return 1;
}

sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

	my $status = 'calculated';
  $$specs{alert} = '';

	$log->debug("START PROOFS!!!!!!!!!!!!!!!!!! ($project_index) ($service_index)") if DEBUG;
	my $Project = new openprint::Project($project_index);
  my $ServiceType = $Project->ServiceType($service_index);

	my @signature_service_indices = $Project->signatures();
	my $minCharge = openprint::service::get_price('ProofsMinimumCharge', undef, undef);
	%ProofServices = map { $_->name(), $_ } openprint::Service->find(
    #servicetype_id=>openprint::ServiceType->find_one(name=>'Proofs')->id());
  servicetype_id=>$ServiceType->id());

	foreach my $qty_index ( $Project->quantity_indexes() ) {
		$$specs{"txtPrice$qty_index"} = '' if ! $$specs{"OverridePrice$qty_index"};
		$$specs{'hdnBreakdown'.$qty_index} = '';

		my $totalPrice = 0;
		my $totalQuantity = 0;

		my %proof_indexes;
		my %proof_types;
		my %proof_totals;
		get_indexes($specs, $qty_index, \%proof_indexes, \%proof_types);

		# First, build a hash containing the quantities of each proof.  The reason for this is to honour quantity discounts.
		foreach my $signature_service_index ( @signature_service_indices ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );

			my $Imposition = new openprint::Imposition();
			$Imposition->load($sig_specs, $qty_index, $Project);
      $$Imposition{service_id} = $signature_service_index;
      my $form = $Imposition->form();

			if (!$$Imposition{imposition}) {
				# Remove it so we don't have to test for it later
				next;
			} # end if
      my $Equipment = $Imposition->Press();

      add_defaults($Project, $ServiceType, $specs, $sig_specs, $qty_index, \%proof_indexes, $Equipment, $Imposition);

			foreach my $proof_index ( @{$proof_indexes{$form}} ) {
				next if !($proof_index and $proof_indexes{$form}[$proof_index]);

				my ( $quantity, $type ) = @$specs{ "txtProofQuantity-$form-$proof_index-$qty_index", "ddmProofType-$form-$proof_index-$qty_index", };
        if ($type) {
          if ( ! $proof_totals{$type} ) {
            $proof_totals{$type} = { Quantity => 0, Price => 0 };
          } # end if
          $proof_totals{$type}{Quantity} += $quantity;
				  $totalQuantity += $quantity;
        }
			} # end foreach my $proof_index
		} # end foreach my $signature_service_index

		foreach my $signature_service_index ( @signature_service_indices ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
			my $Imposition = new openprint::Imposition();
			$Imposition->load( $sig_specs, $qty_index, $Project );
      $$Imposition{service_id} = $signature_service_index;
      my $form = $Imposition->form();
			$$specs{'hdnBreakdown'.$qty_index} .= "Signature $form";
			if (!$$Imposition{imposition}) {
				# Remove it so we don't have to test for it later
				$$specs{'hdnBreakdown'.$qty_index} .= 'No proofs needed because there is no imposition<br/>';
				next;
			} # end if
			my $Equipment = $Imposition->Press();
			$$specs{'hdnBreakdown'.$qty_index} .= ' printed '.$Imposition->to_string().'</br>';
			my %Results = signature_calc( $Project, $ServiceType, $specs, $sig_specs, $qty_index, \%proof_indexes, \%proof_totals, $Equipment, $Imposition );
			$totalPrice += $Results{total};
			$$specs{"hdnBreakdown$qty_index"} .= $Results{Breakdown};
			$status = $Results{status} if $Results{status};
		} # end foreach my $signature_service_index

		if ( $minCharge and ( $totalPrice < $minCharge ) and $totalQuantity ) {
			$totalPrice = $minCharge;
		} # end if

		$totalPrice *= (1+$Project->markup()/100) if $Project->markup();
    $totalPrice *= (1+$$specs{"Markup$qty_index"}/100) if $$specs{"Markup$qty_index"};

		$$specs{"txtPrice$qty_index"} = sprintf($openprint::config{ProjectMoneyFormat}, $totalPrice) if !$$specs{"OverridePrice$qty_index"};
	} # end foreach qty_index

	$log->debug('PROOFS!!!!!!!!!!!!!!!!!!') if DEBUG;
	return $$specs{Status} = $status;
} # end sub calc

sub add_defaults {
	my ( $Project, $ServiceType, $specs, $sig_specs, $qty_index, $indexes, $equipment, $Imposition ) = @_;
  my $form = $Imposition->form();
	if ( !$equipment ) {
		$openprint::log->error('Looking up equipment in Proofs: signature_calc');
		$equipment = openprint::Equipment->find_one(strid => $$sig_specs{'ddmPress'.$qty_index});
		if ( !$equipment ) {
			$openprint::log->warn('Proofs: signature_calc: No equipment for ' . $$sig_specs{'ddmPress'.$qty_index});
			return;
		}
	}
  $$indexes{$form} = [] if ! $$indexes{$form};
  $log->debug('Proof indexes for form '.$form.' at beginning of add_defaults:'.join(',', map { $_ ? $_ : () } @{$$indexes{$form}})) if DEBUG;
  $$specs{RequireLayoutProofs} //= '';
  if (!$$indexes{$form}[LAYOUT_PROOF]) {
    #$log->debug("Don't have layout proof");
    #if (($$specs{RequireLayoutProofs} eq 'Y') or
    #(($$specs{RequireLayoutProofs} ne 'N') and $openprint::config{Add_Default_Layout_Proof} and ($openprint::config{Add_Default_Layout_Proof} eq 'Y'))
    #) {
      #$log->debug("Adding layout proof");
      $$indexes{$form}[LAYOUT_PROOF] = LAYOUT_PROOF;
      #} # end if
  } # end if

  $$specs{RequireColourProofs} //= '';
  if (!$$indexes{$form}[COLOUR_PROOF]) {
    #if (($$specs{RequireColourProofs} eq 'Y') or (
    #($$specs{RequireColourProofs} ne 'N') and $openprint::config{Add_Default_Colour_Proof} and ($openprint::config{Add_Default_Colour_Proof} eq 'Y'))
    #) {
       $$indexes{$form}[COLOUR_PROOF] = COLOUR_PROOF;
       #}
  } # end if

  $$specs{RequirePDFProofs} //= '';
  if (!$$indexes{$form}[PDF_PROOF]) {
    #if (($$specs{RequirePDFProofs} eq 'Y') or (
    #( $$specs{RequirePDFProofs} ne 'N') and $openprint::config{Add_Default_PDF_Proof} and ($openprint::config{Add_Default_PDF_Proof} eq 'Y'))
    #) {
      $$indexes{$form}[PDF_PROOF] = PDF_PROOF;
      #}
  } # end if

  $$specs{RequirePressProofs} //= '';
  #$log->debug("RequirePressProofs $$specs{RequirePressProofs}");
  if (!$$indexes{$form}[PRESS_PROOF]) {
    if (
      ($$specs{RequirePressProofs} eq 'Y') 
        or
      ( 
        ($$specs{RequirePressProofs} ne 'N')  # auto
          and
        (
          ( $openprint::config{Add_Default_Press_Proof} and ($openprint::config{Add_Default_Press_Proof} eq 'Y') ) 
            or 
          ($$sig_specs{rdbPressProof} and ($$sig_specs{rdbPressProof} eq 'Y'))
            or
          ($_ = $Project->Company()->add_press_proofs() and $_->value() and ($_->value() eq 'Y') ) 
        )
      ) 
    ) {
      $$indexes{$form}[PRESS_PROOF] = PRESS_PROOF;
    } else {
      $$indexes{$form}[PRESS_PROOF] = 0;
    }
  } # end if

  if (!$$indexes{$form}[FOLDING_PROOF]) {
    $$specs{RequireFoldingProofs} //= '';
    my $binding = $Project->get_book_type() // '';
    #$openprint::log->debug("BINDERY $binding");
    if (
      ($$specs{RequireFoldingProofs} eq 'Y')
        or 
      (
        ($$specs{RequireFoldingProofs} ne 'N')
          and
        ($binding and sets::isin($binding, ['SaddleStitching', 'LoopStitching', 'PerfectBound', 'PerfectBinding']))
          and $openprint::config{Add_Default_Folding_Proof} eq 'Y'
      )
    ) {
      $$indexes{$form}[FOLDING_PROOF] = FOLDING_PROOF;
    } else {
      #$$indexes{$form}[FOLDING_PROOF] = undef;
      $log->debug("Not adding folding proof");
    } # end if
  } # end if

  $log->debug('Proof indexes for form '.$form.':'.join(',', map { $_ ? $_ : () } @{$$indexes{$form}})) if DEBUG;

  for my $proof_index (5..8) {
    if ($$specs{"txtProofQuantity-$form-$proof_index-$qty_index"}) {
      $$indexes{$form}[$proof_index] = $proof_index;
    }
  }

  my $signature_quantity = $$sig_specs{txtSignatureQuantity} || 1;
	$log->debug('297 Proof indexes for form '.$form.':'.join(',', map { $_ ? $_ : () } @{$$indexes{$form}})) if DEBUG;
	foreach my $proof_index ( @{$$indexes{$form}} ) {
		next if ! ($proof_index and $$indexes{$form}[$proof_index]);
    $$specs{"OverridePrice-$form-$proof_index-$qty_index"} //= '';
    $$specs{"OverrideSize-$form-$proof_index-$qty_index"} //= '';
    $$specs{"OverrideQuantity-$form-$proof_index-$qty_index"} //= '';

			if ( $proof_index == LAYOUT_PROOF ) {
				insert_layout_proof($sig_specs, LAYOUT_PROOF, $qty_index, $specs, $Imposition);
			} elsif ( $proof_index == COLOUR_PROOF ) {
				insert_colour_proof($Project, $sig_specs, COLOUR_PROOF, $qty_index, $specs, $Imposition);
			} elsif ( $proof_index == PRESS_PROOF ) {
				insert_press_proof($Project, $sig_specs, PRESS_PROOF, $qty_index, $specs, $Imposition);
			} elsif ( $proof_index == FOLDING_PROOF ) {
				insert_folding_proof($Project, $sig_specs, FOLDING_PROOF, $qty_index, $specs, $Imposition);
			} elsif ( $proof_index == PDF_PROOF ) {
				insert_pdf_proofs($Project, $sig_specs, PDF_PROOF, $qty_index, $specs, $Imposition);
      } else {
        # Not one of the defined 4 types, so just an extra...How can we do defaults for a random proof type?
        # How about we don't?
        #my $paper = $Imposition->Paper();
        #insert_new_proof( $specs, $proof_index, $form, $signature_quantity, $paper->width(), $paper->height(), 
        #$$specs{"ddmProofType-$form-$proof_index-$qty_index"}, $qty_index );
			} # end if
      #} else {
      #my $force_qty = $openprint::config{'Force'.$$specs{"ddmProofType-$form-$proof_index-$qty_index"}.'Quantity'};
      #
      #if ($force_qty and  ( $$specs{"txtProofQuantity-$form-$proof_index-$qty_index"} < $force_qty ) ) {
      #$$specs{alert} .= "We require ".$force_qty.' '.$$specs{"ddmProofType-$form-$proof_index-$qty_index"}." Proofs<br/>";
      #insert_layout_proof($sig_specs, 1, $qty_index, $specs, $Imposition);
      #} # end if
      #} # end if override or requires forced
  } # end foreach proof
} # end sub add defaults

sub signature_calc {
	my ( $Project, $ServiceType, $specs, $sig_specs, $qty_index, $indexes, $totals, $Equipment, $Imposition ) = @_;

	my %Results = ( Breakdown => '' );

  add_defaults($Project, $ServiceType, $specs, $sig_specs, $qty_index, $indexes, $Equipment, $Imposition);
	my $form = $Imposition->form();
	$log->debug('334 Proof indexes for form '.$form. ':'.join(',', map { $_ ? $_ : () } @{$$indexes{$form}})) if DEBUG;

	%ProofServices = map { $_->name(), $_ } openprint::Service->find(
    #servicetype_id=>openprint::ServiceType->find_one(name=>'Proofs')->id(),
    servicetype_id=>$ServiceType->id()
  ) if !%ProofServices;

	foreach my $proof_index ( @{$$indexes{$form}} ) {
		next if ! ($proof_index and $$indexes{$form}[$proof_index]);
		my ( $quantity, $type ) = @$specs{"txtProofQuantity-$form-$proof_index-$qty_index", "ddmProofType-$form-$proof_index-$qty_index"};
    my ($proof_width, $proof_height) = @$specs{"txtProofWidth-$form-$proof_index-$qty_index", "txtProofHeight-$form-$proof_index-$qty_index"};
    $proof_width ||= 0;
    $proof_height ||= 0;

		if ( !($type and $quantity and ($type ne 'None')) ) {
			if ( DEBUG ) {
        $type //= '';
        $quantity //= 0;
				$log->debug("Next because no type or quantity for sig $form proof $proof_index qty_index $qty_index type $type qty $quantity");
			} # end if
      $$specs{join('-','ServicePrice',$form,$proof_index,$qty_index)} = sprintf($openprint::config{UnitPriceFormat}, 0);
      $$specs{join('-','ServiceUnits',$form,$proof_index,$qty_index)} = '';
      $$specs{"txtProofUnitPrice-$form-$proof_index-$qty_index"} = sprintf($openprint::config{ProjectMoneyFormat}, 0);
			next;
		} # end if
		
		my %MakeReady = openprint::service::get_price_object($type.'MakeReady', $$totals{$type}{Quantity}, undef);
		if ( !%MakeReady ) {
			$MakeReady{price} = 0;
      $MakeReady{units} = '';
		}
		$$specs{join('-','MRPrice',$form,$proof_index,$qty_index)} = $MakeReady{price};
		my %price;

		my $ProofService = $ProofServices{$type};
		if ( $ProofService ) {
      $openprint::log->debug("Proofs service: $$ProofService{name}");
			if ( $type eq 'PressProof' ) {
				%price = $ProofService->get_price($$totals{$type}{Quantity}, $Equipment);
			} else {
				%price = $ProofService->get_price($$totals{$type}{Quantity});
        if ($price{range_units} and (lc $price{range_units} eq 'square inches')) {
          #$openprint::log->error("Getting price by range_units $proof_width, $proof_height = ".($proof_width * $proof_height));

				  %price = $ProofService->get_price($proof_width * $proof_height);
          #$openprint::log->error("Getting price by range_units $proof_width, $proof_height = ".($proof_width * $proof_height).Data::Dumper::Dumper(\%price));
          #} else {
          #$openprint::log->error("Not Getting price by range_units $price{range_units} $proof_width, $proof_height = ".($proof_width * $proof_height).Data::Dumper::Dumper(\%price));
        }
			} # end if
		} # end if
    $price{price} = 0 if ! defined $price{price};
		$price{units} = 'each' if ! $price{units};
		$$specs{join('-','ServicePrice',$form,$proof_index,$qty_index)} = sprintf($openprint::config{UnitPriceFormat}, $price{price});
		$$specs{join('-','ServiceUnits',$form,$proof_index,$qty_index)} = $price{units};

		$Results{Breakdown} .= "Proof: $proof_index: Quantity: $quantity, Type: $type $proof_width x $proof_height";
		if ( $price{units} eq 'per square inch' ) {
			$Results{status} = 'uncalculated' if ! $proof_width * $proof_height;
			$price{total} = Math::Round::nearest( 0.01, $price{price} * $proof_width * $proof_height * $quantity );
			$Results{Breakdown} .= sprintf('MR: %.2f + %d * %sx%s * $%.2f%s=$%.2f<br/>', $MakeReady{price}, $quantity, $proof_width, $proof_height, @price{'price','units','total'} );
		} elsif ( $price{units} eq 'per square foot' ) {
			$Results{status} = 'uncalculated' if ! $proof_width * $proof_height;
			$price{total} = $price{price} * $proof_width * $proof_height / 144 * $quantity;
			$Results{Breakdown} .= sprintf('MR: %.2f + %d * %sx%s * $%.2f%s=$%.2f<br/>', $MakeReady{price}, $quantity, $proof_width, $proof_height, @price{'price','units','total'} );
		} elsif ($price{units} eq 'each' or lc($price{units}) eq 'per proof') {
			$price{total} = $price{price} * $quantity;
			$Results{Breakdown} .= sprintf('MR: $%.2f + %d*$%.2f%s=$%.2f<br/>', $MakeReady{price}, $quantity, @price{'price','units','total'} );
    } else {
			$price{total} = $price{price} * $quantity;
			$Results{Breakdown} .= sprintf('MR: %.2f + %d*$%.2f%s=$%.2f<br/>', $MakeReady{price}, $quantity, @price{'price','units','total'} );
      $Results{Breakdown} .= '<div class="error">Warning unsupported units for '.$ProofService->description().'</div>';
		} # end if
		$$specs{"txtProofUnitPrice-$form-$proof_index-$qty_index"} = sprintf($openprint::config{ProjectMoneyFormat}, $price{total});
		$Results{total} += $price{total} + $MakeReady{price};
	} # end foreach my $proof_index
	$Results{total} = Math::Round::nearest(0.01, $Results{total});
	return %Results;
} # end sub signature_calc

sub delete_proofs {
	my ( $Project, $service_index, $signature_service_index, $qty_index ) = @_;

	my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
	my $form = $$sig_specs{Form} || $$sig_specs{SignatureIndex} || 1;
	$_ = 'SELECT COUNT(strValue) FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND lngServiceIndex=? AND strName LIKE?';
	my ( $number_of_proofs ) = sql::execute( undef, undef, $_, $Project->id(), $service_index, "txtProofQuantity-$form-%-$qty_index" );
	$number_of_proofs = 3 if $number_of_proofs < 3;

	foreach my $proof_index ( 1 .. $number_of_proofs ) {
		sql::execute( undef, undef, q{DELETE FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND lngServiceIndex=? AND strName=?}, $Project->id(), $service_index, "txtProofQuantity-$form-$proof_index-$qty_index" );
		sql::execute( undef, undef, q{DELETE FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND lngServiceIndex=? AND strName=?}, $Project->id(), $service_index, "txtProofWidth-$form-$proof_index-$qty_index" );
		sql::execute( undef, undef, q{DELETE FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND lngServiceIndex=? AND strName=?}, $Project->id(), $service_index, "txtProofHeight-$form-$proof_index-$qty_index" );
		sql::execute( undef, undef, q{DELETE FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND lngServiceIndex=? AND strName=?}, $Project->id(), $service_index, "ddmProofType-$form-$proof_index-$qty_index" );
	} # end foreach

} # end sub delete_proofs

# Deletes stale data, and inserts default Proofs For the supplied signature
sub insert_proofs {
	my ( $Project, $service_index, $signature_service_index, $qty_index ) = @_;

	my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
	my $Imposition = new openprint::Imposition();
	$Imposition->load( $sig_specs, $qty_index, $Project );
	my $specs = openprint::service::get_specs_ref( $Project, $service_index );

	my $ac = sql::start_transaction( $dbh );
	delete_proofs( $Project, $service_index, $signature_service_index, $qty_index );
	my @scanning_indices;
	my $services = $Project->services();

	if ( $$services{Scanning} ) {
		foreach my $index ( @{$$services{Scanning}} ) {
			my $scanning_specs = openprint::service::get_specs_ref( $Project, $index );
			if ( $$scanning_specs{rdbRandomProof} eq 'Yes' ) {
				push @scanning_indices, $index;
			} # end if
		} # end foreach scanning index
	} # end if Scanning

	if ( sets::isin( $signature_service_index, \@scanning_indices ) ) {
		insert_scanning_proof( $Project, $signature_service_index, 1, $qty_index, $specs );
	} else {
		insert_colour_proof( $Project, $sig_specs, 1, $qty_index, $specs, $Imposition );
		insert_layout_proof( $sig_specs, 2, $qty_index, $specs, $Imposition );
		insert_folding_proof( $sig_specs, 4, $qty_index, $specs, $Imposition );
	} # end if
	sql::end_transaction( $dbh, $ac );
} # end sub insert_proofs

sub insert_scanning_proof {
	my ( $Project, $scanning_service_index, $proof_index, $qty_index, $specs ) = @_;

	my $sig_specs = openprint::service::get_specs_ref( $Project, $scanning_service_index );
	insert_new_proof( $specs, $proof_index, undef, @$sig_specs{'txtQuantity','txtScanWidthFinal','txtScanHeightFinal'}, 'EpsonProof', $qty_index );
} # end sub insert_scanning_proof

sub insert_folding_proof {
  my ( $Project, $sig_specs, $proof_index, $qty_index, $specs, $Imposition ) = @_;
  my $form = $Imposition->form();

  my $equipment = $Imposition->Press();
  if ( ! $equipment ) {
    $openprint::log->error("No equipment in insert_foldingproof");
    $equipment = openprint::Equipment->find_one( strid=>$$sig_specs{'ddmPress'.$qty_index} ) if $$sig_specs{'ddmPress'.$qty_index};
    if ( ! $equipment ) {
      $openprint::log->error("No equipment in insert_foldingproof");
    } # end if
  } # end if

  my ($default_proof_type) = $equipment->specification('Default Folding Proof') if $equipment;
  if (!$default_proof_type) {
    $openprint::log->debug('No Default Folding Proof for ' . $equipment->strid() ) if DEBUG and $equipment;
    $default_proof_type = $openprint::config{Default_Folding_Proof} // '';
  } elsif (DEBUG) {
    $openprint::log->debug('Default Folding Proof for ' . $equipment->strid().' is ' .$default_proof_type ) if $equipment;
  }
  return if $default_proof_type and ($default_proof_type eq 'None');

  my $proofer = $equipment;

  # Layout proof might be a reduced laser. Need to get size from the proofer or press
  my $service = openprint::Service->find_one(name=>$default_proof_type) if $default_proof_type;
  $log->debug("No service foudn for $default_proof_type from $$equipment{name}") if !$service;
  my %prices_by_equipment_id = map { $$_{equipment_id} => $_ } $service->Prices() if $service;
  if (exists $prices_by_equipment_id{$$equipment{id}}) {
    $proofer = $equipment;
  } elsif ( 1 == keys %prices_by_equipment_id) {
    $proofer = (values %prices_by_equipment_id)[0]->Equipment();
  } else {
    $log->debug("Unable to choose default folding proof equipment" . Data::Dumper::Dumper(\%prices_by_equipment_id));
  }

  $log->debug("Using $$proofer{name} for equipment") if DEBUG;
  my ($width, $height, $sides) = $proofer->specifications(
    'Default Folding Proof Width','Default Folding Proof Height', 'Folding Proof Sides');
  ($width, $height) = ( $Imposition->sheet_width(), $Imposition->sheet_height()) if (!($width and $height));
  if ($$specs{"OverrideSize-$form-$proof_index-$qty_index"} eq 'Y') {
    ($width, $height) = @$specs{"txtProofWidth-$form-$proof_index-$qty_index", "txtProofHeight-$form-$proof_index-$qty_index"};
  }

  my $quantity = 0;
  if ($$specs{"OverrideQuantity-$form-$proof_index-$qty_index"} eq 'Y') {
    $quantity = int($$specs{"txtProofQuantity-$form-$proof_index-$qty_index"});
  } else {
    #$$sig_specs{SideOneColours} = [openprint::Estimating::Printing::get_colours( $sig_specs, 'SideOne' )] if ! $$sig_specs{SideOneColours};
    #$$sig_specs{SideTwoColours} = [openprint::Estimating::Printing::get_colours( $sig_specs, 'SideTwo' )] if ! $$sig_specs{SideTwoColours};
    if ( (!$$specs{RequireFoldingProofs}) or ($$specs{RequireFoldingProofs} ne 'N') ) {
      #if ( $$Imposition{runstyle} and sets::isin( $$Imposition{runstyle}, ['Web','Sheet Work','Perfecting'] ) ) {
      #$quantity += 1 if @{$$sig_specs{SideOneColours}};
      #$quantity += 1 if @{$$sig_specs{SideTwoColours}} and ((!$sides) or ($sides ne 'Both'));
      #} else {
      #$quantity += 1 if @{$$sig_specs{SideOneColours}} or @{$$sig_specs{SideTwoColours}};
      #} # end if
      $quantity += 1;
    } # end if
    my $signature_quantity = $$sig_specs{txtSignatureQuantity} || 1;
    $quantity *= $signature_quantity;
  }

	insert_new_proof( $specs, $proof_index, $Imposition->form(), $quantity, $width, $height, $default_proof_type, $qty_index );
} # end sub insert_Folding_proof

sub insert_press_proof {
	my ( $Project, $sig_specs, $proof_index, $qty_index, $specs, $Imposition ) = @_;
  my $form = $Imposition->form();

	$$sig_specs{SideOneColours} = [openprint::Estimating::Printing::get_colours($sig_specs, 'SideOne')] if ! $$sig_specs{SideOneColours};
	$$sig_specs{SideTwoColours} = [openprint::Estimating::Printing::get_colours($sig_specs, 'SideTwo')] if ! $$sig_specs{SideTwoColours};
	my $quantity = 0;
  if ($$specs{"OverrideQuantity-$form-$proof_index-$qty_index"} eq 'Y') {
    $quantity = int($$specs{"txtProofQuantity-$form-$proof_index-$qty_index"});
  }  else {
    if ( (!$$specs{RequirePressProofs}) or ($$specs{RequirePressProofs} ne 'N') ) {
      if ( $$Imposition{runstyle} and sets::isin( $$Imposition{runstyle}, ['Web','Sheet Work','Perfecting'] ) ) {
        $quantity += 1 if @{$$sig_specs{SideOneColours}};
        $quantity += 1 if @{$$sig_specs{SideTwoColours}};
      } else {
        $quantity += 1 if @{$$sig_specs{SideOneColours}} or @{$$sig_specs{SideTwoColours}};
      } # end if
    } # end if
  } # end if
  $log->debug("insert_new_proof($specs, $proof_index, $form, $quantity, $Imposition->sheet_width(), $Imposition->sheet_height(), 'PressProof', $qty_index )");
	insert_new_proof($specs, $proof_index, $form, $quantity, $Imposition->sheet_width(), $Imposition->sheet_height(), 'PressProof', $qty_index );
} # end sub insert_press_proof

sub insert_pdf_proofs {
	my ( $Project, $sig_specs, $proof_index, $qty_index, $specs, $Imposition ) = @_;
  my $Equipment = $Imposition->Press();
  my $form = $Imposition->form();
	$$sig_specs{SideOneColours} = [openprint::Estimating::Printing::get_colours( $sig_specs, 'SideOne' )] if ! $$sig_specs{SideOneColours};
	$$sig_specs{SideTwoColours} = [openprint::Estimating::Printing::get_colours( $sig_specs, 'SideTwo' )] if ! $$sig_specs{SideTwoColours};

  my $quantity = 0;
  my $proof_type = $$specs{"ddmProofType-$form-$proof_index-$qty_index"};
  if (!$proof_type) {
    my ( $default_proof_type ) = $Equipment->specification('Default PDF Proof') // '' if $Equipment;
    $openprint::log->debug("Default proof type on $$Equipment{name} is: $default_proof_type") if DEBUG;
    $default_proof_type = $openprint::config{'Default_PDF_Proof'} // '' if ! $default_proof_type;
    $proof_type ||= $default_proof_type;
  }
  if ($$specs{"OverrideQuantity-$form-$proof_index-$qty_index"} eq 'Y') {
    $quantity = int($$specs{"txtProofQuantity-$form-$proof_index-$qty_index"});
  } else {
    if ( $proof_type and ($proof_type ne 'None')) {
      if ($$specs{RequirePDFProofs} eq 'N') {
        $quantity = 0;
      } elsif ($$specs{RequirePDFProofs} ne 'N') {
        # Auto or Y
        $quantity += 1 if $$sig_specs{chkProcessColourSideOne} or $$sig_specs{s0_process};
        #$quantity += 1 if $$sig_specs{chkProcessColourSideTwo} or ($$sig_specs{s1_process}) or ($$sig_specs{s0_process} and $$sig_specs{side_link});
      } # end if
    }
  }
  if (!$proof_type) {
    $$specs{alert} .= 'No proof type for pdf proofs<br/>';
    return;
  }

  my $proof_service = openprint::Service->find_one(name=>$proof_type);
  if (!$proof_service) {
    $$specs{alert} .= 'No proof service for '.$proof_type.'<br/>';
    $proof_type =~ s/\s//g;
    $proof_service = openprint::Service->find_one(name=>$proof_type);
  }
  if (!$proof_service) {
    $$specs{alert} .= 'No proof service for '.$proof_type.'<br/>';
    return;
  }
  my @prices = $proof_service->Prices();
  my %prices_by_equipment_id = map { $$_{equipment_id} => $_ } $proof_service->Prices();

  my $proofer;
  if (exists $prices_by_equipment_id{$$Equipment{id}}) {
    $proofer = $Equipment;
  } elsif ( 1 == keys %prices_by_equipment_id) {
    $proofer = (values %prices_by_equipment_id)[0]->Equipment();
  } else {
    $proofer = $prices[0]->Equipment();
  }
  my $signature_quantity = $$sig_specs{txtSignatureQuantity} || 1;
  $quantity *= $signature_quantity;

  insert_new_proof( $specs, $proof_index, $form, $quantity,  '', '', $proof_type, $qty_index );
} # end sub insert_pdf_proofs

# Colour proofs are generally used for CMYK jobs, not black/PMS only
sub insert_colour_proof {
  my ( $Project, $sig_specs, $proof_index, $qty_index, $specs, $Imposition ) = @_;
  my $form = $Imposition->form();

  $$sig_specs{SideOneColours} = [openprint::Estimating::Printing::get_colours( $sig_specs, 'SideOne' )] if ! $$sig_specs{SideOneColours};
  $$sig_specs{SideTwoColours} = [openprint::Estimating::Printing::get_colours( $sig_specs, 'SideTwo' )] if ! $$sig_specs{SideTwoColours};
  $log->debug("*** Inserting Colour Proof *******" .@{$$sig_specs{SideOneColours}}.'/'.@{$$sig_specs{SideTwoColours}}) if DEBUG;
  my $Equipment = $Imposition->Press();
	if (!$Equipment) {
		$openprint::log->error('No equipment in insert_colour_proof');
		$Equipment = openprint::Equipment->find_one( strid=>$$sig_specs{'ddmPress'.$qty_index} ) if $$sig_specs{'ddmPress'.$qty_index};
		$Equipment = openprint::Equipment->find_one( id=>$$sig_specs{hdnPress} ) if (!$Equipment) and $$sig_specs{hdnPress};
		if (!$Equipment) {
			$openprint::log->error('No equipment in insert_colour_proof');
		} # end if
	} # end if

  my $width = $$Imposition{object_width};
  my $height = $$Imposition{object_height};
  my ( $proof_style ) = $Equipment->specification('Colour Proof Style') // '';

  my $proof_type = $$specs{"ddmProofType-$form-$proof_index-$qty_index"};
  if (!$proof_type) {
    my ( $default_proof_type ) = $Equipment->specification('Default Colour Proof') // '' if $Equipment;
    ( $default_proof_type ) = $openprint::config{'Default Colour Proof'} if !$default_proof_type;
    $openprint::log->debug("Default proof type on $$Equipment{name} is: $default_proof_type") if DEBUG;
    $proof_type ||= $default_proof_type;
  }

  my $quantity = 0;
  if ($$specs{"OverrideQuantity-$form-$proof_index-$qty_index"} eq 'Y') {
    $quantity = int($$specs{"txtProofQuantity-$form-$proof_index-$qty_index"});
  } else {
    if ($proof_type and ($proof_type ne 'None')) {
      if ($$specs{RequireColourProofs} eq 'N') {
        $quantity = 0;
      } elsif ($$specs{RequireColourProofs} ne 'N') {
        # Auto or Y
        $quantity += 1 if $$sig_specs{chkProcessColourSideOne} or $$sig_specs{s0_process};
        $quantity += 1 if $$sig_specs{chkProcessColourSideTwo} or ($$sig_specs{s1_process}) or ($$sig_specs{s0_process} and $$sig_specs{side_link});
      } # end if
    }
    # we need extra proofs for business cards.
    if ($$sig_specs{txtNameQuantity} and ($$sig_specs{txtNameQuantity} > 1)) {
      $quantity *= $$sig_specs{txtNameQuantity};
    } # end if
    if ($Project->type() eq 'MultiPage') {
      if ( $$sig_specs{'PageQuantity'.$qty_index} and ( $$sig_specs{'PageQuantity'.$qty_index} > 1) ) {
        $quantity *= $$sig_specs{'PageQuantity'.$qty_index} / $$sig_specs{txtSpreadSize} if $$sig_specs{txtSpreadSize};
      } # end if
    } # end if
  }

  if ($quantity and !$proof_type) {
    $$specs{alert} .= 'No proof type for colour proofs.<br/>';
  }

  if ($proof_type and ($proof_type ne 'None')) {
    my $proof_service = openprint::Service->find_one(name=>$proof_type);
    if (!$proof_service) {
      $$specs{alert} .= 'No proof service for '.$proof_type.'<br/>';
      $proof_type =~ s/\s//g;
      $proof_service = openprint::Service->find_one(name=>$proof_type);
    }
    if (!$proof_service) {
      $$specs{alert} .= 'No proof service for '.$proof_type.'<br/>';
      return;
    }
    my @prices = $proof_service->Prices();

    my %prices_by_equipment_id = map { $$_{equipment_id} => $_ } $proof_service->Prices() if $proof_service;

    my $proofer;
    if (exists $prices_by_equipment_id{$$Equipment{id}}) {
      $proofer = $Equipment;
    } elsif ( 1 == keys %prices_by_equipment_id) {
      $proofer = (values %prices_by_equipment_id)[0]->Equipment();
      ($width, $height) = $proofer->specifications('Default Layout Proof Width','Default Layout Proof Height');
    } else {
      $proofer = $prices[0]->Equipment();
    }
    $openprint::log->debug("Proofer: ".$proofer->name(). ' style: '.$proof_style) if DEBUG;

    if ($proof_style and ($proof_style eq 'Multiple')) {
      # Select the first proofer sorted by strid that has pricing for our Proof Type to get our Max size from.

      # Get max size for the proofer.
      my ( $maxwidth, $maxheight ) = $proofer->specifications('Maximum Sheet Width', 'Maximum Sheet Length') if $proofer;
      if ($maxwidth and $maxheight) {
        # If our Proof Style is multiple then increase our proof size until we have everything down to 1 proof
        # or we have hit the max size for the proofer.
        my $w = $width;
        my $h = $height;
        my $q = $quantity;
        my $x = $q % 2;

        # Keep going checking quantity and with/height or
        # rotated with/height against our max dimensions
        while (($q > 1) && ($x == 0) && ( ($h <= $maxheight && $w <= $maxwidth) or ($w <= $maxheight && $h <= $maxwidth))) {
          # Store the current valid sizes.
          $width = $w;
          $height = $h;
          $quantity = $q;
          # Make a squareish proof by increasing the smaller side each time.
          if ( $w < $h ) { $w *= 2; } else { $h *= 2 }

          # Right now we are only handling multiples of 2.
          # So unless our $qty can be diveded evenly by 2 then we must stop.
          $x = $q % 2;

          # Cut the quantity of proofs in half cause we have double the size of the proof
          $q /= 2;
        } # end while
      } # end if maxwidth and height
    } else {
      ($width, $height) = $proofer->specifications('Default Layout Proof Width','Default Layout Proof Height');
    } # end if style = Multiple

    ($width, $height) = @$Imposition{'object_width','object_height'} if !($width and $height);
	} # end if has default proof type

  if ($$specs{"OverrideSize-$form-$proof_index-$qty_index"} eq 'Y') {
    ($width, $height) = @$specs{"txtProofWidth-$form-$proof_index-$qty_index", "txtProofHeight-$form-$proof_index-$qty_index"};
  }
  # only if project requires 4 colour process.
	insert_new_proof($specs, $proof_index, $form, $quantity, $width, $height, $proof_type, $qty_index);
} # end sub insert_colour_proof

sub insert_layout_proof {
	my ( $sig_specs, $proof_index, $qty_index, $specs, $Imposition ) = @_;
  my $form = $Imposition->form();

	my $equipment = $Imposition->Press();
	if ( ! $equipment ) {
		$openprint::log->error("No equipment in insert_layout_proof");
		$equipment = openprint::Equipment->find_one( strid=>$$sig_specs{'ddmPress'.$qty_index} ) if $$sig_specs{'ddmPress'.$qty_index};
		if ( ! $equipment ) {
			$openprint::log->error("No equipment in insert_layout_proof");
		} # end if
	} # end if

  my $proof_type = $$specs{"ddmProofType-$form-$proof_index-$qty_index"};
  if (!$proof_type) {
    my ($default_proof_type) = $equipment->specification('Default Layout Proof') if $equipment;
    if (!$default_proof_type) {
      $openprint::log->debug('No Default Layout Proof for ' . $equipment->strid() ) if DEBUG and $equipment;
      $default_proof_type = $openprint::config{Default_Layout_Proof} // '';
    } elsif (DEBUG) {
      $openprint::log->debug('Default Layout Proof for ' . $equipment->strid().' is (' .$default_proof_type.')' ) if $equipment;
    }
    return if $default_proof_type and ($default_proof_type eq 'None');
    $proof_type = $default_proof_type;
  }

  my $proofer = $equipment;
  # Layout proof might be a reduced laser. Need to get size from the proofer or press
  my $service = openprint::Service->find_one(name=>$proof_type) if $proof_type;
  $log->error("No service foudn for $proof_type") if $proof_type and !$service;
  my %prices_by_equipment_id = map { $$_{equipment_id} => $_ } $service->Prices() if $service;
  if (exists $prices_by_equipment_id{$$equipment{id}}) {
    $proofer = $equipment;
  } elsif ( 1 == keys %prices_by_equipment_id) {
    $proofer = (values %prices_by_equipment_id)[0]->Equipment();
  } else {
    $log->error("Unable to choose default layout proof size");
  }
  $log->debug("Using $$proofer{name} for equipment");
  my ($width, $height, $sides) = $proofer->specifications(
    'Default Layout Proof Width','Default Layout Proof Height', 'Layout Proof Sides');
  ($width, $height) = @$Imposition{'sheet_width sheet_height'} if !($width and $height);
  if ($$specs{"OverrideSize-$form-$proof_index-$qty_index"} eq 'Y') {
    ($width, $height) = @$specs{"txtProofWidth-$form-$proof_index-$qty_index", "txtProofHeight-$form-$proof_index-$qty_index"};
  }
	my $quantity = 0;
  if ($$specs{"OverrideQuantity-$form-$proof_index-$qty_index"} eq 'Y') {
    $quantity = int($$specs{"txtProofQuantity-$form-$proof_index-$qty_index"});
  } else {
    if (($$specs{RequireLayoutProofs} eq 'Y') or
      (($$specs{RequireLayoutProofs} ne 'N') and $openprint::config{Add_Default_Layout_Proof} and ($openprint::config{Add_Default_Layout_Proof} eq 'Y'))
    ) {
      $$sig_specs{SideOneColours} = [openprint::Estimating::Printing::get_colours($sig_specs, 'SideOne')] if ! $$sig_specs{SideOneColours};
      $$sig_specs{SideTwoColours} = [openprint::Estimating::Printing::get_colours($sig_specs, 'SideTwo')] if ! $$sig_specs{SideTwoColours};
      #$log->debug("Imposition".Data::Dumper::Dumper($Imposition));
      if ( sets::isin( $$Imposition{runstyle}, ['Web', 'Sheet Work', 'Perfecting'] ) ) {
        $quantity += 1 if @{$$sig_specs{SideOneColours}};
        $quantity += 1 if @{$$sig_specs{SideTwoColours}} and (!$sides or $sides ne 'Both');
      } else {
        $quantity += 1 if @{$$sig_specs{SideOneColours}} or @{$$sig_specs{SideTwoColours}};
      } # end if
      my $signature_quantity = $$sig_specs{txtSignatureQuantity} || 1;
      $quantity *= $signature_quantity;
    }
  }

	insert_new_proof( $specs, $proof_index, $form, $quantity,  $width, $height, $proof_type, $qty_index );
} # end sub insert_layout_proof

sub insert_new_proof {
	my ( $specs, $proof_index, $form, $qty, $width, $height, $type, $qty_index ) = @_;
  $form //= 1;
	$$specs{"txtProofQuantity-$form-$proof_index-$qty_index"} = $qty;
	$$specs{"txtProofWidth-$form-$proof_index-$qty_index"} = defined($width) ? $width : '';
	$$specs{"txtProofHeight-$form-$proof_index-$qty_index"} = defined($height) ? $height : '';
	$$specs{"ddmProofType-$form-$proof_index-$qty_index"} = $type;
	$$specs{"txtProofIndex-$form-$proof_index-$qty_index"} = $proof_index;
} # end sub insert_new_proof

sub load_proof_info {
	my ( $Project, $service_index, $form, $qty_index, $specs ) = @_;

	my @proof_info = ();

	$specs = openprint::service::get_specs_ref( $Project, $service_index ) if ! $specs;

	my @proofs;
	foreach my $key ( keys %$specs ) {
		if ( $key =~ /^txtProofIndex-$form-\d+-$qty_index$/ ) {
			push @proofs, $$specs{$key};
		} # end if
	} # end foreach
	foreach my $proof_index ( sort @proofs ) {
    my ( $quantity, $width, $height, $type ) = @$specs{
    "txtProofQuantity-$form-$proof_index-$qty_index",
    "txtProofWidth-$form-$proof_index-$qty_index",
    "txtProofHeight-$form-$proof_index-$qty_index",
    "ddmProofType-$form-$proof_index-$qty_index"
    };
    push @proof_info, $proof_index, $quantity, 1*$width, 1*$height, $type;
	} # end foreach
	return @proof_info;
} # end sub load_proof_info

sub display {
	my ($log, $dbh, $variable, $project_index, $service_index) = @_;

	my $Project = openprint::Project->find_one(id=>$project_index);
  if (!$Project) {
    $log->error("No project for $project_index");
    return 'uncalculated';
  }

	my $services = $Project->services();
  my $ServiceType = $Project->ServiceType($service_index);
  #my @service_dropdown = map { $_->name(), $_->description() } openprint::Service->find(servicetype_id=>$ServiceType->id());

	my $specs = openprint::service::get_specs_ref($Project, $service_index);
	foreach my $qty_index ( $Project->quantity_indexes() ) {
		my %proof_indexes;
		foreach my $key ( keys %$specs ) {
			if ( $key =~ /^txtProofIndex-(\d+)-(\d+)-$qty_index$/ ) {
				$proof_indexes{$1}[$$specs{$key}] = $$specs{$key};
			} # end if
		} # end foreach

		foreach my $signature_service_index ( $Project->signatures() ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
			my $Imposition = new openprint::Imposition();
			$Imposition->load($sig_specs, $qty_index, $Project);
      $$Imposition{service_id} = $signature_service_index;
      my $form = $Imposition->form();
			if (!$$Imposition{imposition}) {
				$log->warn("No imposition in signature $form") if DEBUG;
				next;
			} # end if
			my $Equipment = $Imposition->Press();
			$Imposition->display( "For sig $form") if DEBUG;
      add_defaults($Project, $ServiceType, $specs, $sig_specs, $qty_index, \%proof_indexes, $Equipment, $Imposition);

			$$variable{'Proofs-'.$form.'-'.$qty_index} = [];
			next if ! $proof_indexes{$form};
			foreach my $proof_index ( sort map { $_ ? $_ : () } @{$proof_indexes{$form}} ) {
				my ( $quantity, $width, $height, $type ) = @$specs{map{join('-',$_,$form,$proof_index,$qty_index)}
					('txtProofQuantity', 'txtProofWidth', 'txtProofHeight', 'ddmProofType')
				};
$openprint::log->debug("Have $quantity $width x $height $type for form $form qty $qty_index");
				push @{$$variable{'Proofs-'.$form.'-'.$qty_index}}, $proof_index, $quantity, 1*$width, 1*$height, $type;
			} # end foreach proof
		} # end foreach signature
	} # end foreach qty_index

	@{$$variable{SignatureGroups}} = ();
	foreach my $signature_service_index ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref($Project, $signature_service_index);
    # Imposition->form should have updated sig_specs
		push @{$$variable{SignatureGroups}}, @$sig_specs{qw(Form txtServiceDescription)};
	} # end foreach signature

# Now do scanning
	if ( $$services{Scanning} ) {
		foreach my $index ( @{$$services{Scanning}} ) {
			my $scanning_specs = openprint::service::get_specs_ref($Project, $index);
			if ( $$scanning_specs{rdbRandomProof} eq 'Yes' ) {
# add a scanning proof
				push @{$$variable{SignatureGroups}}, $$scanning_specs{Form}, 'Scanning Proof';
				@{$$variable{'Proofs'.$$scanning_specs{Form}}} = load_proof_info( $Project, $service_index, $$scanning_specs{Form} );
			} # end if
		} # end foreach scanning service
	} # end if

} # end sub display

sub save {
	my ( $project_index, $service_index, $new_specs ) = @_;

	$log->debug('In Save Proof Specs');

	my $Project = new openprint::Project($project_index);
	my $Service = $Project->Service($service_index);

	if ( $$new_specs{RequirePressProofs} and ($$new_specs{RequirePressProofs} eq 'N') ) {
		foreach my $sig_id ( $Project->signatures() ) {
			openprint::service::insert_service_spec($openprint::log, $openprint::dbh, $project_index, $sig_id, 'rdbPressProof', '');
		}
	}

	my $redirect = 0;

# Now check to see if we need to add more proofs, and redirect back
	foreach my $key ( keys %{$new_specs} ) {
		if ( $key =~ /rdbAdditional-(\d*)-(\d*)/ ) {
			if ( $$new_specs{$key} eq 'Yes' ) {
				my $form = $1;

				my $ac = sql::start_transaction($openprint::dbh);
        $_ = 'SELECT lngServiceIndex FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND strName=? AND strValue=?';
        my ( $signature_service_index ) = sql::execute(undef, undef, $_, $project_index, 'Form', $form);
        if (!$signature_service_index) {
          $_ = 'SELECT lngServiceIndex FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND strName=? AND strValue=?';
          ( $signature_service_index ) = sql::execute(undef, undef, $_, $project_index, 'SignatureIndex', $form);
        }

				foreach my $qty_index ( $Project->quantity_indexes() ) {
					my ( $proof_index ) = sql::execute(undef, undef,
							'SELECT MAX(strValue::integer) FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND lngServiceIndex=? AND strName LIKE ?',
							$project_index, $service_index, "txtProofIndex-$form-%-$qty_index");
					$proof_index += 1;
					$proof_index = 4 if $proof_index < 4;

					openprint::service::insert_service_spec($openprint::log, $openprint::dbh, $project_index, $service_index, "txtProofQuantity-$form-$proof_index-$qty_index", 1 );
					openprint::service::insert_service_spec($openprint::log, $openprint::dbh, $project_index, $service_index, "txtProofWidth-$form-$proof_index-$qty_index", '' );
					openprint::service::insert_service_spec($openprint::log, $openprint::dbh, $project_index, $service_index, "txtProofHeight-$form-$proof_index-$qty_index", '' );
					openprint::service::insert_service_spec($openprint::log, $openprint::dbh, $project_index, $service_index, "ddmProofType-$form-$proof_index-$qty_index", '' );
					openprint::service::insert_service_spec($openprint::log, $openprint::dbh, $project_index, $service_index, "txtProofIndex-$form-$proof_index-$qty_index", $proof_index );
				} # end foreach

				sql::end_transaction($openprint::dbh, $ac);

				$redirect = 1;
			} # end if
		} # end if
	} # end foreach

	if ( $redirect ) {
		$openprint::variable{Redirect} = '/main/project/'.$Service->ServiceType()->url();
	} else {
		if ( $$new_specs{'txtPrice1'} > 0 || $$new_specs{'txtPrice2'} > 0 || $$new_specs{'txtPrice3'} > 0 ) {
			$Service->save({status=>'calculated'});
		} # end if
	} # end if
} # end sub save

sub summary {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;
	$specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;
	if ( $qty_index ) {
		my %proof_totals;
		foreach my $ss_id ( $Project->signatures() ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
			my $Imposition = new openprint::Imposition();
			$Imposition->load($sig_specs, $qty_index, $Project);
      $$Imposition{service_id} = $ss_id;
			if (!$Imposition->imposition()) {
				next;
			} # end if
      my $form = $$sig_specs{Form} || $$sig_specs{SignatureIndex} || 1;
			foreach my $key ( keys %{$specs} ) {
				if ( my ($proof_index) = $key =~ /^txtProofIndex\-$form\-(\d+)\-$qty_index$/ ) {
					next if ! $$specs{"ddmProofType-$form-$proof_index-$qty_index"};
          next if ! $$specs{"txtProofQuantity-$form-$proof_index-$qty_index"};

					if ( my $Service = openprint::Service->find_one(name=>$$specs{"ddmProofType-$form-$proof_index-$qty_index"}) ) {
						if ( sets::isin( $$specs{"ddmProofType-$form-$proof_index-$qty_index"}, [ 'PressProof', 'PDFProof' ] ) ) {
              my $desc = sprintf('</td><td class="type">%s', $Service->description() );
              $proof_totals{$desc} += $$specs{"txtProofQuantity-$form-$proof_index-$qty_index"};
						} else {
							my $desc = sprintf('%s&quot;x%s&quot;</td><td class="type">%s', @$specs{
									"txtProofWidth-$form-$proof_index-$qty_index",
									"txtProofHeight-$form-$proof_index-$qty_index"}, $Service->description() );
							$proof_totals{$desc} += $$specs{"txtProofQuantity-$form-$proof_index-$qty_index"};
						} # end if
					} # end if
				} # end if
			} # end foreach key
		} # end foreach signature
		if ( ! %proof_totals ) {
			return '';
		} # end if
		my $summary = '<table class="ProofsSummary">';
		foreach my $k ( sort keys %proof_totals ) {
			next if ! $proof_totals{$k};
			$summary .= '<tr><td class="quantity">'.$proof_totals{$k}.'</td><td class="size">'.$k.'</td></tr>';
		} # end foreach
		return $summary.'</table>';
	} # end if qty_index
	return '';
} # end sub summary

sub signature_summary {
  my ( $Project, $service_id, $specs, $qty_index, $ss_id ) = @_;
  $specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;
  if ( $qty_index ) {
    my %proof_totals;
    my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
    my $Imposition = new openprint::Imposition();
    $Imposition->load($sig_specs, $qty_index, $Project);
    if (!$Imposition->imposition()) {
			next;
		} # end if
    my $form = $$sig_specs{Form} || $$sig_specs{SignatureIndex} || 1;
		foreach my $key ( keys %{$specs} ) {
			if ( my ($proof_index) = $key =~ /^txtProofIndex\-$form\-(\d+)\-$qty_index$/ ) {
				if ( my $Service = openprint::Service->find_one( name=>$$specs{"ddmProofType-$form-$proof_index-$qty_index"}) ) {
					if ( sets::isin( $$specs{"ddmProofType-$form-$proof_index-$qty_index"}, [ 'PressProof', 'PDFProof' ] ) ) {
						my $desc = sprintf('</td><td class="type">%s', $Service->description() );
						$proof_totals{$desc} += $$specs{"txtProofQuantity-$form-$proof_index-$qty_index"};
					} else {
						my $desc = sprintf('%s&quot;x%s&quot;</td><td class="type">%s', @$specs{
								"txtProofWidth-$form-$proof_index-$qty_index",
								"txtProofHeight-$form-$proof_index-$qty_index"}, $Service->description() );
						$proof_totals{$desc} += $$specs{"txtProofQuantity-$form-$proof_index-$qty_index"} if $$specs{"txtProofQuantity-$form-$proof_index-$qty_index"};
					} # end if
				} # end if
			} # end if
		} # end foreach key
		if ( ! %proof_totals ) {
			return '';
		} # end if
		my $summary = '<table class="ProofsSummary">';
		foreach my $k ( keys %proof_totals ) {
			next if ! $proof_totals{$k};
			$summary .= '<tr><td class="quantity">'.$proof_totals{$k}.'</td><td class="size">'.$k.'</td></tr>';
		} # end foreach
		return $summary.'</table>';
		} # end if qty_index
		return '';
} # end sub signature_summary

sub breakupsummary {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;

	my $Currency = openprint::Currency::get_current();
	$specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;
	if ( $qty_index ) {
		my %proof_totals;
		my %proof_tot;
		my %Totprice;
		foreach my $ss_id ( $Project->signatures() ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
			my $form = $$sig_specs{Form};
			foreach my $key ( keys %{$specs} ) {
				if ( my ($proof_index) = $key =~ /^txtProofIndex-$form-(\d*)-$qty_index$/ ) {
					my $Service = openprint::Service->find_one('name'=>$$specs{"ddmProofType-$form-$proof_index-$qty_index"});
					if ( $Service ) {	
						my $desc = sprintf('<td align="left">%s&quot;x%s&quot;</td><td align="left">%s', @$specs{
								"txtProofWidth-$form-$proof_index-$qty_index",
								"txtProofHeight-$form-$proof_index-$qty_index"}, $Service->description() );
						my $qty = $$specs{"txtProofQuantity-$form-$proof_index-$qty_index"} // 0;
						if ( $qty != 0 ) {
							$proof_totals{$desc} += $$specs{"txtProofQuantity-$form-$proof_index-$qty_index"};
							my $Uprice   = $$specs{"txtProofUnitPrice-$form-$proof_index-$qty_index"};
							my $type = @$specs{"ddmProofType-$form-$proof_index-$qty_index"};
							if ( ! $proof_tot{$type} ) {
								$proof_tot{$type} = { Quantity => 0, Price => 0 };
							} # end if
							$proof_tot{$type}{Quantity} += $qty;
							my %MkReady  = openprint::service::get_price_object( $type.'MakeReady', $proof_tot{$type}{Quantity}, undef );
							$Totprice{$desc} += ($Uprice*$qty) + ($MkReady{price}//0);
						} # end if
					} # end if
				} # end if
			} # end foreach key
		} # end foreach signature
##		my $summary = '<table class = "insideservice" style="width:auto;table-layout:auto;">';
		my $summary = '<table>';

		foreach my $k ( keys %proof_totals ) {
			next if ! $proof_totals{$k};
			$summary .= '<tr><td>'.$proof_totals{$k}.'&nbsp;&nbsp;&nbsp;</td>'.$k.'&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</td>';
			$summary .= '<td class="Price">'.sprintf('%s%.2f',$Currency->symbol(), $Totprice{$k}).'</td></tr>';
		} # end foreach
		return $summary.'</table>';
	} # end if qty_index
	return '';
} # end sub breakupsummary

sub project_summary {
	my ( $Project, $service_id, $specs ) = @_;
	$specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;

	my %types;

	foreach my $ss_id ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
		my $form = $$sig_specs{SignatureIndex} || $$sig_specs{Form} || 1;
		foreach my $key ( keys %{$specs} ) {
			if ( my ($proof_index, $qty_index) = $key =~ /^txtProofIndex-$form-(\d*)-(\d*)$/ ) {
				next if ! $$specs{"ddmProofType-$form-$proof_index-$qty_index"};
				next if ! $$specs{"txtProofQuantity-$form-$proof_index-$qty_index"};
				if ( my $Service = openprint::Service->find_one(name=>$$specs{"ddmProofType-$form-$proof_index-$qty_index"}) ) {
					$types{$Service->description()} = 1;
				} # end if
			} # end if
		} # end foreach key
	} # end foreach signature
	return ' ' . join(',', keys %types) . '<br/>' if %types;
  return '';
} # end sub project_summary

sub has_overrides {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;

	# None of our overrides are quantity independent
	return if ! $qty_index;

	$specs = openprint::service::get_specs_ref($Project, $service_id) if ! $specs;

	my @v;

	foreach my $ss_id ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
		my $form = $$sig_specs{Form};
		foreach my $key ( keys %{$specs} ) {
			if ( $key =~ /^txtProofIndex-$form-(\d+)-$qty_index$/ ) {
				my ( $proof_index ) = ( $1 );
        foreach my $field ('OverrideSize','OverridePrice') {
					push @v, "$field-$form-$proof_index-$qty_index" if $$specs{"$field-$form-$proof_index-$qty_index"};
				} # end foreach field
			} # end if
		} # end foreach key
	} # end foreach signature
  push @v, "OverridePrice$qty_index" if $$specs{"OverridePrice$qty_index"};
  return @v;
} # end sub has_overrides

sub status {
	my ( $Project, $service_id, $specs ) = @_;
	$specs = openprint::service::get_specs_ref($Project, $service_id) if !$specs;

	my $status;
	if ( $$specs{rdbApproved} and ($$specs{rdbApproved} eq 'Yes') ) {
		$status = 'Approved';
	} elsif ( $$specs{rdbClientApproved} and ($$specs{rdbClientApproved} eq 'Y') ) {
		$status = 'Waiting For QA Approval';
	} elsif ( $$specs{rdbComplete} and ($$specs{rdbComplete} eq 'Yes') ) {
		$status = 'Proofs out';
	} else {
		$status = 'Ordered'
	}	
	return $status;
} # end sub status

1;
__END__
