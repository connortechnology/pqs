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

package openprint::Estimating::VariableData;
use strict;
use warnings;

require sql;
require openprint::service;

my @variables = (
    'txtPrice1', 'txtPrice2', 'txtPrice3',
    'Markup1', 'Markup2', 'Markup3',
    'OverridePrice1', 'OverridePrice2', 'OverridePrice3',
    'txtQuantity1', 'txtQuantity2', 'txtQuantity3',
    'VariableBWTextStreamQty',
    'VariableTextStreamQty',
    'VariableImageStreamQty',
    'VariableColourTextStreamQty',
    'VariableColourImageStreamQty',
    'VariableDataVerificationQty',
);

sub variables { return @variables; }

my @no_output = (
    'ProjectIndex','ServiceIndex','ServiceType',
    'txtQuantity1', 'txtQuantity2', 'txtQuantity3',
    'Markup1', 'Markup2', 'Markup3',
    'OverridePrice1', 'OverridePrice2', 'OverridePrice3',
    'VariableBWTextStreamQty',
    'VariableTextStreamQty',
    'VariableImageStreamQty',
    'VariableColourTextStreamQty',
    'VariableColourImageStreamQty',
    'VariableDataVerificationQty',
    'VariableBWTextStreamQty',
    );

sub no_outputs { return @no_output; } # end sub no_outputs

sub neccessary {
	my ( $Project ) = @_;
	my $services = $Project->services();
	if ( $$services{NoBindery} ) {
		return 0;
	} # end if

	return 0;
} # end sub needed

sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

	my $Project = new openprint::Project( $project_index );
	my $services = $Project->services();
  my $ServiceType = $Project->ServiceType($service_index);
  $$specs{alert} = '';

	my $minimumCharge = openprint::service::get_price( 'VariableDataMinimumCharge', undef, undef );

  my @equipment = openprint::Equipment->find(
      'servicetype_id any'=>$ServiceType->id(),
      useinestimating=>1);
  if (!@equipment) {
    $$specs{alert} = 'We have no equipment for '.$ServiceType->description().'<br/>';
    return $$specs{Status} = 'uncalculated';
  } # end if

  my $have_stream = 0;
  foreach my $stream (
      'VariableBWTextStream',
      'VariableTextStream',
      'VariableImageStream',
      'VariableColourTextStream',
      'VariableColourImageStream',
      'VariableDataVerification',
      ) {
    if ($$specs{$stream.'Qty'} and int($$specs{$stream.'Qty'})) {
      $have_stream = 1;
      last;
    }
  }
  if (!$have_stream) {
    $$specs{alert} .= 'Please enter the number of variable data streams<br/>';
  }

  my $printing_specs = $$services{''} ? openprint::service::get_specs_ref( $Project, $$services{''}[0] ) : {};

  foreach my $qty_index ( $Project->quantity_indexes() ) {
    $$specs{"txtQuantity$qty_index"} =~ s/\D//g;
    $$specs{"txtQuantity$qty_index"} = $Project->quantity( $qty_index ) if ! $$specs{"txtQuantity$qty_index"};
    my $qty = $$specs{"txtQuantity$qty_index"};
    $qty *= $$printing_specs{PageQuantity} if $$printing_specs{PageQuantity};
		$$specs{'hdnBreakdown'.$qty_index} = '';
  
    my %bestPrice;

    foreach my $equipment (@equipment) {
      my %price = (
          MakeReadyTotal => 0,
          ServicePriceTotal => 0,
          Total => 0,
          Equipment => $equipment,
          );

      foreach my $stream (
          'VariableBWTextStream',
          'VariableTextStream',
          'VariableImageStream',
          'VariableColourTextStream',
          'VariableColourImageStream',
          'VariableDataVerification',
          ) {
        next if (!$$specs{$stream.'Qty'} or !int($$specs{$stream.'Qty'}));
          
        my $MakeReadyService = openprint::Service->find_one(name=>$stream.'MakeReady');
        $MakeReadyService = openprint::Service->find_one(name=>$ServiceType->name().'MakeReady') if !$MakeReadyService;

        if ($MakeReadyService) {
          my %MakeReadyPrice = $MakeReadyService->get_price(undef, $equipment);
          $price{MakeReadyService} = $MakeReadyService;
          $price{MakeReadyPrice} = \%MakeReadyPrice;
          $MakeReadyPrice{Price} //= 0;

          $price{Breakdown}  .= $MakeReadyService->description(). ' ' . sprintf( '%.2f', $MakeReadyPrice{Price} ) . '<br/>';

          $price{MakeReadyTotal} += $MakeReadyPrice{Price};
          $price{Total} += $MakeReadyPrice{Price};
        } # end if MR 

        my $Service = openprint::Service->find_one(name=>$stream);
        $Service = openprint::Service->find_one(name=>$ServiceType->name()) if ! $Service;
        if ($Service) {
          $price{Breakdown} .= $Service->description();
          my %ServicePrice = $Service->get_price($qty, $equipment);

          $ServicePrice{units} //= 'per m';
          if ( sets::isin( lc $ServicePrice{units}, ['per m', 'per 1000'] ) ) {
            $ServicePrice{Total} = $ServicePrice{Price} * $qty / 1000;
            $price{Breakdown} .= sprintf(': $%.2f%s * %d=$%.2f<br/>' , @ServicePrice{'Price','units'}, $qty, $ServicePrice{Total} );
          } elsif ( sets::isin( lc $ServicePrice{units}, ['each'] ) ) {
            $ServicePrice{Total} = $ServicePrice{Price} * $qty;
            $price{Breakdown} .= sprintf(': $%.2f%s * %d=$%.2f<br/>' , @ServicePrice{'Price','units'}, $qty, $ServicePrice{Total} );
          } else {
            $price{alert} .= sprintf('Unknown units for service price %s $%.2f%s<br/>', @ServicePrice{'ServiceName','Price','units'} );
            $price{Breakdown} .= sprintf('Unknown units for service price %s $%.2f%s<br/>', @ServicePrice{'ServiceName','Price','units'} );
          } # end if
          $price{ServicePriceTotal} += $ServicePrice{Total};
          $price{Total} += $ServicePrice{Total};
        } # end if Service
      } # end foreach stream

      if ($minimumCharge and ($price{Total} < $minimumCharge)) {
        $price{Breakdown} .= 'MinimumCharge: ' . sprintf( '%.2f', $minimumCharge ) . '<br/>';
        $price{Total} = $minimumCharge;
      } # end if

      if ((!%bestPrice) or $bestPrice{Total} > $price{Total}) {
        %bestPrice = %price;
      }
    }  # end foreach Equipment

		$$specs{'hdnBreakdown'.$qty_index} = $bestPrice{Breakdown};
    $$specs{alert} .= $bestPrice{alert};
    my $price = $bestPrice{Total};
    if ($Project->markup()) {
      $price *= (1+$Project->markup()/100);
    }
    if ($$specs{"Markup$qty_index"}) {
      $price *= (1+$$specs{"Markup$qty_index"}/100);
    }
		$$specs{"txtUnitPrice$qty_index"} = sprintf( $openprint::config{UnitPriceFormat}, $price / $qty);
		$$specs{"MPrice$qty_index"} = sprintf($openprint::config{UnitPriceFormat}, $bestPrice{ServicePriceTotal} / 1000);
		if ( $$specs{'OverridePrice'.$qty_index} eq 'Y' ) {
			$$specs{"txtPrice$qty_index"} = sprintf($openprint::config{ProjectMoneyFormat}, $$specs{"txtPrice$qty_index"});
		} else {
			$$specs{"txtPrice$qty_index"} = sprintf($openprint::config{ProjectMoneyFormat}, $price);
		} # end if
	} # end foreach qty_index
	return $$specs{Status} = 'calculated';
} # end sub calc

sub summary {
} # end sub summary

sub save {
} # end sub save

sub display {
} # end sub display

sub has_overrides {
  my ( $Project, $service_id, $specs, $qty_index ) = @_;
  $specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;

  my @v;
  if ( $qty_index ) {
      push @v, "OverridePrice$qty_index" if $$specs{"OverridePrice$qty_index"};
  } # end if

  return @v;
} # end sub has_overrides

1;
__END__
