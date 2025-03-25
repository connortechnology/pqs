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

package openprint::Estimating::Counting;
use strict;

require sql;
require openprint::service;

use vars qw( %ServicePrices %Specifications);
%ServicePrices = (
  CountingMinimumCharge => {},
  CountingMakeReady => {},
  Counting => { units=> ['each', 'per m']},
);
%Specifications = (
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
    'txtSignatureCount',
    'txtPrice1', 'txtPrice2', 'txtPrice3',
    'Markup1', 'Markup2', 'Markup3',
    'OverridePrice1', 'OverridePrice2', 'OverridePrice3',
    'txtQuantity1', 'txtQuantity2', 'txtQuantity3',
    'comments',
);

sub variables { return @variables; }

my @no_output = (
    'ProjectIndex','ServiceIndex','ServiceType',
    'txtQuantity1', 'txtQuantity2', 'txtQuantity3',
	'Markup1', 'Markup2', 'Markup3',
	'OverridePrice1', 'OverridePrice2', 'OverridePrice3',
);

sub no_outputs { return @no_output; } # end sub no_outputs

sub neccessary {
	my ( $Project ) = @_;
	my $services = $Project->services();
	if ( $$services{NoBindery} ) {
		return 0;
	} # end if

	foreach my $ServiceType ( openprint::ServiceType->find('category'=>'Packaging') ) {
#$openprint::log->debug("Counting neccessary: ServiceType: " . $ServiceType->name());
		next if ! $$services{$ServiceType->name()};
		foreach my $s_id ( @{$$services{$ServiceType->name()}} ) {
			my $specs = openprint::service::get_specs_ref( $Project, $s_id );
#$openprint::log->debug("Counting neccessary: Accurate Count: " . $$specs{AccurateCount} );
			return 1 if $$specs{AccurateCount} eq 'Y';
		} # end foreach s_id
	} # end foreach ServiceType
	return 0;
} # end sub needed

sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

	my $Project = new openprint::Project( $project_index );
	my $services = $Project->services();

	my $makeReadyPrice = openprint::service::get_price( 'CountingMakeReady', undef, undef );
	my $minimumCharge = openprint::service::get_price( 'CountingMinimumCharge', undef, undef );

# This is just a display field for the docket. The number is the size of
# the piles to group projects into when counting. 
  $$specs{txtSignatureCount} = int($specs->{txtSignatureCount}) || 1;

	foreach my $qty_index ( $Project->quantity_indexes() ) {
		$$specs{"txtQuantity$qty_index"} =~ s/\D//g;
		$$specs{"txtQuantity$qty_index"} = $Project->quantity( $qty_index ) if ! $$specs{"txtQuantity$qty_index"};
		my $qty = $$specs{"txtQuantity$qty_index"};

		if ( $$services{''} ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] );
			$qty *= $$sig_specs{PageQuantity} if $$sig_specs{PageQuantity};
		} # end if

		$$specs{'hdnBreakdown'.$qty_index} = '';
		$$specs{'hdnBreakdown'.$qty_index} .= 'MakeReady: ' . sprintf( '%.2f', $makeReadyPrice ) . '<br/>';
		$$specs{'hdnBreakdown'.$qty_index} .= 'MinimumCharge: ' . sprintf( '%.2f', $minimumCharge ) . '<br/>';

		my %ServicePrice = openprint::service::get_price_object( 'Counting', $qty, undef );
		if ( sets::isin( lc $ServicePrice{units}, ['per m', 'per 1000'] ) ) {
			$ServicePrice{Total} = $ServicePrice{Price} * $qty / 1000;
			$$specs{'hdnBreakdown'.$qty_index} .= sprintf('ServiceCharge: $%.2f%s * %d=$%.2f<br/>' , @ServicePrice{'Price','units'}, $qty, $ServicePrice{Total} );
		} elsif ( sets::isin( lc $ServicePrice{units}, ['each'] ) ) {
			$ServicePrice{Total} = $ServicePrice{Price} * $qty;
			$$specs{'hdnBreakdown'.$qty_index} .= sprintf('ServiceCharge: $%.2f%s * %d=$%.2f<br/>' , @ServicePrice{'Price','units'}, $qty, $ServicePrice{Total} );
		} else {
			$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Unknown units for Counting service price $%.2f%s<br/>', @ServicePrice{'Price','units'} );
		} # end if
		my $price = $makeReadyPrice + $ServicePrice{Total};
		if ( $minimumCharge > 0 and $price < $minimumCharge ) {
			$price = $minimumCharge;
		} # end if

		$$specs{"txtUnitPrice$qty_index"} = sprintf( $openprint::config{UnitPriceFormat}, 
( $price / $qty ) * (1+$Project->markup()/100) );
		if ( $$specs{'OverridePrice'.$qty_index} eq 'Y' ) {
			$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, $$specs{"txtPrice$qty_index"} );
		} else {
			$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, $price*(1+$$specs{"Markup$qty_index"}/100)*(1+$Project->markup()/100) );
		} # end if
	} # end foreach
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
