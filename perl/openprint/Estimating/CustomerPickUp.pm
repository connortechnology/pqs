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

package openprint::Estimating::CustomerPickUp;
use strict;
use POSIX qw(ceil);

require sql;
require sets;

my %variables = (
	'txtPackageQuantity1' => ['save','output'],
	'txtPackageQuantity2' => ['save','output'],
	'txtPackageQuantity3' => ['save','output'],
	'txtPrice1'=>['save'], 'txtPrice2'=>['save'], 'txtPrice3'=>['save'],
	'txtQuantity1'=>['save','output'], 'txtQuantity2'=>['save','output'], 'txtQuantity3'=>['save','output'],
	'chkOverridePackageQuantity'=>['save'],
	'txtTotalWeight1'=>['save','output'], 'txtTotalWeight2'=>['save','output'], 'txtTotalWeight3'=>['save','output'],
	'txtPackageWeight'=>['save','output'],
	'txtPackageWeight1'=>['save','output'],
	'txtPackageWeight2'=>['save','output'],
	'txtPackageWeight3'=>['save','output'],
	alert	=> ['save','output' ],
);

sub variables {
  my @v;
  foreach my $k ( keys %variables ) {
    push @v, $k, if sets::isin( 'save', $variables{$k} );
  } # end foreach;
  return @v;
}

sub no_outputs {
  my @v;
  foreach my $k ( keys %variables ) {
    push @v, $k, if ! sets::isin( 'output', $variables{$k} );
  } # end foreach;
  return @v;
}

sub has_overrides {
  my ( $Project, $service_id, $specs, $qty_index ) = @_;
  $specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;

  my @v;
  if ( $qty_index ) {
  } else {
    push @v, map { $$specs{$_} ? $_ : () } (
      'chkOverridePackageQuantity',
    );
  } # end if

  return @v;

} # end sub has_overrides


sub calc {
  my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

  my $status = 'calculated';
  $$specs{alert} = '';

  my $Project = new openprint::Project( $project_index );
  my $services = $Project->services();
  my $carton_service_index = $$services{PlainCartons}[0] if $$services{PlainCartons} and @{$$services{PlainCartons}};
  ( $carton_service_index ) = $$services{BulkSkids}[0] if $$services{BulkSkids} and @{$$services{BulkSkids}};
  if ( ! $carton_service_index ) {
    $$specs{alert} .= 'Project must be in cartons or on skids.<br/>';
    return $$specs{Status} = 'uncalculated';
  } # end if
  my $CartonService = $Project->Service($carton_service_index);
  if ('uncalculated' eq $CartonService->status()) {
    $$specs{alert} .= $CartonService->name().' service has not been calculated yet.';
    return $$specs{Status} = 'uncalculated';
  } # end if
  my $carton_specs = openprint::service::get_specs_ref( $Project, $carton_service_index );

  my @shipping_services;
  foreach my $ServiceType ( openprint::ServiceType->find('category'=>'Shipping') ) {
    next if ! $$services{$ServiceType->name()};
    foreach ( @{$$services{$ServiceType->name()}} ) {
      push @shipping_services, $_ if $_ != $service_index;
    } # end foreach
  } # end foreach ServiceType

  foreach my $qty_index ( $Project->quantity_indexes() ) {
    # Ensure Cardinality of Quantity
    $$specs{'txtQuantity'.$qty_index} =~ s/\D//g;
    $$specs{'txtQuantity'.$qty_index} = $Project->quantity($qty_index) if $$specs{'txtQuantity'.$qty_index} > $Project->quantity($qty_index);

    if ( ! $$carton_specs{"txtItemsPerPackage$qty_index"} ) {
      $$specs{alert} .= 'Unable to determine how many items per package.';
      return $$specs{Status} = 'calculated';
    } # end if

    if ( $$specs{"chkOverridePackageWeight$qty_index"} ne 'Y' ) {
      # Load from skids or cartons
      $$specs{"txtPackageWeight$qty_index"} = $$carton_specs{"txtPackageWeight$qty_index"};
    } # end if

    my $other_shipped_quantity = 0;
    foreach my $sid ( @shipping_services ) {
      my $service_specs = openprint::service::get_specs_ref( $Project, $sid );
      $other_shipped_quantity += $$service_specs{'txtQuantity'.$qty_index};
    } # end foreach sid

    if ( $$specs{'txtQuantity'.$qty_index} == $Project->quantity($qty_index) or ! $$specs{'txtQuantity'.$qty_index} ) {
      $$specs{'txtQuantity'.$qty_index} = $Project->quantity($qty_index) - $other_shipped_quantity;
    } # end if

    if ( $other_shipped_quantity + $$specs{'txtQuantity'.$qty_index} > $Project->quantity( $qty_index ) ) {
      $$specs{alert} .= 'There are more items being shipped or picked up than are being produced. Please edit the quantities being shipped or picked up.'. ($Project->quantity($qty_index) - $other_shipped_quantity) . '<br/>';
      $status = 'uncalculated';
    } # end if

    $$specs{'txtPackageQuantity'.$qty_index} = ceil($$specs{'txtQuantity'.$qty_index}/$$carton_specs{"txtItemsPerPackage$qty_index"});
    $$specs{"txtTotalWeight$qty_index"} = Math::Round::nearest( 0.01, (int( $$specs{'txtQuantity'.$qty_index}/$$carton_specs{"txtItemsPerPackage$qty_index"} ) * $$specs{"txtPackageWeight$qty_index"}) + (($$specs{'txtQuantity'.$qty_index} % $$carton_specs{"txtItemsPerPackage$qty_index"} ) * $$carton_specs{txtFinishedWeight}) );
  } # end foreach

  return $$specs{Status} = $status;
} # end sub calc

sub summary {
  my ( $Project, $service_id, $specs, $qty_index ) = @_;
  my $services = $Project->services();
  if ( $qty_index ) {
    if ( $$services{BulkSkids} ) {
      return sprintf( qq{%d items on %d skid%s\nweighing %.2flbs}, @$specs{'txtQuantity'.$qty_index,'txtPackageQuantity'.$qty_index},( $$specs{'txtPackageQuantity'.$qty_index}==1?'' : 's'), $$specs{'txtTotalWeight'.$qty_index} );
    } elsif ( $$services{PlainCartons} ) {
      return sprintf( qq{%d items in %d carton%s\nweighing %.2flbs}, @$specs{'txtQuantity'.$qty_index,'txtPackageQuantity'.$qty_index},( $$specs{'txtPackageQuantity'.$qty_index}==1?'' : 's'), $$specs{'txtTotalWeight'.$qty_index} );
    } # end if
  } # end if
  return '';
} # end sub summary

1;
__END__
