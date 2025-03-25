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

package openprint::Estimating::Imposition;
use strict;
#use Data::Dumper;

use constant DEBUG => 0;

require openprint::service;

my %ServicePrices = (
  '(.*)Imposition(.*)MakeReady' => { units => [ 'per form', 'per side' ] },
  'Imposition' => { units=> ['per page', 'per square inch of layout', 'per square inch of object']},
  'Stepping Charge' => { units=> []},
  'Page Charge' => { units=> ['per page']},
);
my %Specifications = (
);

sub ServicePriceConfiguration {
  my $name = shift;
  return $ServicePrices{$name} if $ServicePrices{$name};
  foreach my $key (keys %ServicePrices) {
    return $ServicePrices{$key} if ($name =~ /$key/i);
  }
  return undef;
}
sub SpecificationConfiguration {
  return $Specifications{shift};
}

my @variables = (
	'txtQuantity1', 'txtQuantity2', 'txtQuantity3',
	'txtUnitPrice1', 'txtUnitPrice2', 'txtUnitPrice3',
	'txtPrice1', 'txtPrice2', 'txtPrice3',
	'hdnBreakdown1',
	'hdnBreakdown2',
	'hdnBreakdown3',
);

sub variables {
    return @variables;
} # end sub variables


sub neccessary {
	#my ( $Project ) = @_;

	return 1 if openprint::ServiceType->find_one(name=>'Imposition');

	return 0;
} # end sub neccessary

my $MRService;
my $SigMRService;
my $ServiceService;
my $SteppingService;
my $PageChargeService;

sub init {
	my ( $Project ) = @_;
	my $type_name = $Project->Type()->name();

	$MRService = openprint::Service->find_one( name=>'ImpositionMakeReady'.$type_name );
	$MRService = openprint::Service->find_one( name=>'ImpositionMakeReady' ) if ! $MRService;

	$SigMRService = openprint::Service->find_one( name=>'SignatureImpositionMakeReady'.$type_name );
	$SigMRService = openprint::Service->find_one( name=>'SignatureImpositionMakeReady' ) if ! $SigMRService;

	$ServiceService = openprint::Service->find_one( name=>'Imposition'.$type_name );
	$ServiceService = openprint::Service->find_one( name=>'Imposition' ) if ! $ServiceService;

	$SteppingService = openprint::Service->find_one( name=>'Stepping Charge'.$type_name );
	$SteppingService = openprint::Service->find_one( name=>'Stepping Charge' ) if ! $SteppingService;

	$PageChargeService = openprint::Service->find_one( name=>'Page Charge'.$type_name );
	$PageChargeService = openprint::Service->find_one( name=>'Page Charge' ) if ! $PageChargeService;
}

sub signature_calc {
	my ( $Project, $Imposition, $previous_forms, $qty_index ) = @_;

	my %price;

	my $Press = $Imposition->Press();

	my %ImpositionMakeReady;
	if ( $SigMRService ) {
		%ImpositionMakeReady = $SigMRService->get_price( undef, $Press );
		if ( %ImpositionMakeReady ) {
			if ( $ImpositionMakeReady{units} eq 'per form' ) {
#$openprint::log->debug("Make Ready Per Form " . ($$specs{'PreviousForms'.$qty_index}+1) );
				%ImpositionMakeReady = $SigMRService->get_price( $previous_forms, $Press );
				$ImpositionMakeReady{Total} = $ImpositionMakeReady{Price}; # * $previous_forms;
			} elsif ( $ImpositionMakeReady{units} eq 'per side' ) {
				$ImpositionMakeReady{Total} = $ImpositionMakeReady{Price} * $Imposition->sides();
			} elsif ( $ImpositionMakeReady{units} eq 'per job' ) {
        my @signatures = $Project->signatures( { sort=>1 } );
        my $sig_specs = openprint::service::get_specs_ref( $Project, $signatures[0] );
        my $specs = $Imposition->specs();
        if ($$specs{SignatureIndex} == $$sig_specs{SignatureIndex}) {
          $ImpositionMakeReady{Total} = $ImpositionMakeReady{Price};
        } else {
          $ImpositionMakeReady{Total} = 0;
        }
			} else {
$openprint::log->error('Unknown units on ImpositionMakeready');
			} # end if
		} elsif(DEBUG) {
			$openprint::log->error('No price found for ' . $SigMRService->name() . ' on '.$$Press{strid});
		} # end if
		if ( DEBUG ) {
			$openprint::log->debug("MR Price is $ImpositionMakeReady{Price}");
		}
	} # end if

	$price{MakeReady} = \%ImpositionMakeReady;
	$price{Total} = $ImpositionMakeReady{Total};

	my %ImpositionCharge;

	if ( $ServiceService ) {
		%ImpositionCharge = $ServiceService->get_price( undef, $Press);
		if ( %ImpositionCharge ) {
			if ( $ImpositionCharge{units} eq 'per page' ) {
				%ImpositionCharge = $ServiceService->get_price( $Imposition->pages(),$Press);
				$price{Total} += $ImpositionCharge{Price} * $Imposition->pages();
			} elsif ( $ImpositionCharge{units} eq 'per square inch of object' ) {
				%ImpositionCharge = $ServiceService->get_price( $Imposition->layout_area(),$Press);
				$price{Total} += $ImpositionCharge{Price} * $Imposition->object_width() * $Imposition->object_height();
			} elsif ( $ImpositionCharge{units} eq 'per square inch of layout' ) {
				%ImpositionCharge = $ServiceService->get_price( $Imposition->layout_area(),$Press);
				$price{Total} += $ImpositionCharge{Price} * $Imposition->layout_area();
			} else {
				%ImpositionCharge = $ServiceService->get_price( $$Imposition{imposition},$Press);
				$price{Total} += $ImpositionCharge{Price} * $$Imposition{imposition};
			} # end if
		} # end if
    $openprint::log->debug("MakeReady is $ImpositionCharge{Price} $ImpositionCharge{units} $ImpositionCharge{Total}") if DEBUG;
  } elsif ( DEBUG ) {
    $openprint::log->debug('NO MR service');
  } # end if SErviceService
  $price{Price} = \%ImpositionCharge;

	my %SteppingCharge;
	if ( $SteppingService ) {
		%SteppingCharge = $SteppingService->get_price( undef, $Press );
		if ( %SteppingCharge ) {
			$SteppingCharge{Total} = $SteppingCharge{Price} * $Imposition->imposition();
			$price{'Stepping Charge'} = \%SteppingCharge;
			$price{Total} += $SteppingCharge{Total};
		} # end if
	} # end if

   if ( $Imposition->pages() and $PageChargeService ) {
		my %PageCharge = $PageChargeService->get_price( $Imposition->pages(), $Press );
		if ( %PageCharge ) {
			if ( $PageCharge{units} eq 'per page' ) {
				$PageCharge{Total} = $PageCharge{Price} * $Imposition->pages();
			} else {
$openprint::log->error("Bad units for Page Page $PageCharge{units}");
			} # end if
			$price{'Page Charge'} = \%PageCharge;
			$price{Total} += $PageCharge{Total};
		} # end if Page Charge
	} # end if pages

#$openprint::log->debug(Data::Dumper::Dumper(\%price));
	return \%price;
} # end sub signature_calc

sub calc {
$openprint::log->debug("Imposition calc: @_");
	shift @_ if $_[0] eq 'openprint::Estimating::Imposition';

	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

	my $status = 'calculated';

	my $Project = new openprint::Project( $project_index );
	#my $services = $Project->services();
	init( $Project );
	my @signatures = $Project->signatures();

	foreach my $qty_index ( $Project->quantity_indexes() ) {
		$$specs{"txtQuantity$qty_index"} = int( $$specs{"txtQuantity$qty_index"} );
		$$specs{"txtQuantity$qty_index"} = $Project->quantity( $qty_index ) if ! $$specs{"txtQuantity$qty_index"};
		$$specs{'hdnBreakdown'.$qty_index} = '';

		my $total = 0;

		my %TotalImpositionMakeReady;
		if ( $MRService ) {
			%TotalImpositionMakeReady = $MRService->get_price( );
			$total += $TotalImpositionMakeReady{Price};

			$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Imposition Charge MR: $%1$.2f<br/>', $TotalImpositionMakeReady{Price} );
		} # end if

		my @Previous_Signatures;

		foreach my $sig_id ( @signatures ) {
      my $sig_specs = openprint::service::get_specs_ref( $Project, $sig_id );
      $$specs{'hdnBreakdown'.$qty_index} .= "For $$sig_specs{txtServiceDescription} form $$sig_specs{SignatureIndex}: ";
      if ( ! $$sig_specs{'txtImposition'.$qty_index} ) {
        $$specs{'hdnBreakdown'.$qty_index} .= "No imposition<br/>";
        next;
      } # end if
			push @Previous_Signatures, $sig_id;
			my $Imposition = new openprint::Imposition();
			$Imposition->load( $sig_specs, $qty_index, $Project );
			my $price = signature_calc( $Project, $Imposition, scalar @Previous_Signatures, $qty_index );
			$total += $$price{Total};

			$$specs{'hdnBreakdown'.$qty_index} .= signature_summary( $Imposition, $price );
		} # end foreach signature
		$$specs{"txtUnitPrice$qty_index"} = sprintf( $openprint::config{UnitPriceFormat}, $total * (1+$Project->markup()/100) );
		$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, $total * (1+$Project->markup()/100) );
	} # end foreach qty_index

	return $$specs{Status} = $status;
} # end sub calc

sub display {
    my ( $log, $dbh, $variable, $project_index, $service_index ) = @_;

	my $Project = new openprint::Project( $project_index );

} # end sub display

sub signature_summary {
  my ( $Imposition, $Price ) = @_;

  my $breakdown = 'Imposition Charge: ';
  my $MakeReady = $$Price{MakeReady};
  my $Service = $$Price{Price};

  if ( $$MakeReady{Price} ) {
    if ( $$MakeReady{units} eq 'per side' ) {

      $breakdown .= sprintf('MR($%1$.2f%2$s = $%3$.2f) ', @$MakeReady{qw(Price units Total)} );
    } else {
      $breakdown .= sprintf('MR($%1$.2f) ', $$MakeReady{Price} );
    } # end if
  } # end if


  if ( $$Service{units} eq 'per page' ) {
    $breakdown .= sprintf('+ $%1$.2f*%3$d pages = $%2$.2f<br/>', $$Service{Price}, $$Price{Total}, $Imposition->pages() );
  } elsif ( $$Service{units} eq 'per square inch of object' ) {
    $breakdown .= sprintf('+ $%1$.2f*%3$s x %4$s = $%2$.2f<br/>', $$Service{Price}, $$Price{Total}, $Imposition->object_width(), $Imposition->object_height() );
  } elsif ( $$Service{units} eq 'per square inch of layout' ) {
    $breakdown .= sprintf('+ $%1$.2f*%4$s x %4$s = $%2$.2f<br/>', $$Service{Price}, @$Price{Total}, $Imposition->layout_width(), $Imposition->layout_height() );
  } elsif ( $$Service{Price} ) {
    $breakdown .= sprintf('+ $%1$.2f*%3$d out = $%2$.2f<br/>', $$Service{Price}, @$Price{Total}, $$Imposition{imposition} );
  } # end if

  if ( my $PageCharge = $$Price{'page charge'} ) {
    $breakdown .= sprintf('Page Charge: $%1$.2f%2$s * %4$d pages = $%3$.2f<br/>', @$PageCharge{'Price','units','Total'}, $Imposition->pages() );
  } # end if
  if ( my $SteppingCharge = $$Price{'stepping charge'} ) {
    $breakdown .= sprintf('Stepping Charge: $%1$.2f%2$s * %4$dout  = $%3$.2f<br/>', @$SteppingCharge{'Price','units','Total'}, $$Imposition{imposition} );
  } # end if
  return $breakdown;
} # end sub signature_summary

sub summary {
  my ( $Project, $service_index, $specs, $qty_index ) = @_;
  if ( $qty_index ) {
    return '';
  } # end if
  return '';
}

sub has_overrides {
  return ();
}

1;
__END__
