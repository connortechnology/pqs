# Copyright (C) 2007 Isaac Connor <isaac@connortechnology.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA	02110-1301, USA

use strict;
use warnings;
package openprint::Estimating::Shipping;
use POSIX qw{ ceil };

require openprint::Company;
require sql;
require sets;

use constant DEBUG=>0;

my %variables = (
	txtPrice1=>['save','output'], txtPrice2=>['save','output'], txtPrice3=>['save','output'],txtPriceUsed=>['save'],
	OverridePrice1	=>	['save'], OverridePrice2	=>	['save'], OverridePrice3	=>	['save'],
	txtQuantity1=>['save','output'], txtQuantity2=>['save','output'], txtQuantity3=>['save','output'],txtQuantityUsed=>['save'],
	txtPackageQuantity1=>['save','output'], txtPackageQuantity2=>['save','output'], txtPackageQuantity3=>['save','output'],txtPackageQuantityUsed=>['save','output'],
	chkOverridePackageQuantity => ['save'],
	txtTotalWeight1=>['save','output'], txtTotalWeight2=>['save','output'], txtTotalWeight3=>['save','output'],txtTotalWeightUsed=>['save','output'],
	txtPackageWeight1=>['save','output'], txtPackageWeight2=>['save','output'], txtPackageWeight3=>['save','output'],txtPackageWeightUsed=>['save','output'],

	FromCompanyName=>['save'],FromAddress1=>['save'],FromAddress2=>['save'],FromCity=>['save'],FromStateProvince=>['save'],FromCountry=>['save'],FromPostalCode=>['save'],FromPhone=>['save'],FromFax=>['save'],FromEmail=>['save'],
	ToCompanyName=>['save'],ToAddress1=>['save'],ToAddress2=>['save'],ToCity=>['save'],ToStateProvince=>['save'],ToCountry=>['save'],ToPostalCode=>['save'],ToPhone=>['save'],ToFax=>['save'],ToEmail=>['save'],
	FromFirstName=>['save'],FromLastName=>['save'],
	ToFirstName=>['save'],ToLastName=>['save'],
	alert=>['save','output'],
	to_company_id	=>	['save'],
	from_company_id	=>	['save'],
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
    push @v, map { $$specs{$_.$qty_index} ? $_ : () } (
      'OverridePrice','chkOverridePackageWeight',
    );
  } else {
    push @v, map { $$specs{$_} ? $_ : () } (
      'chkOverridePackageQuantity',
    );
  } # end if

  return @v;
} # end sub has_overrides


sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

	my $Project = new openprint::Project($project_index);
	my $Project_Service = $Project->Service( $service_index );
	my $services = $Project->services();
	$$specs{alert} = '';
	my $status = 'calculated';
	my $carton_service_index = $$services{PlainCartons}[0] if $$services{PlainCartons} and @{$$services{PlainCartons}};
	if (!$carton_service_index) {
		if ($openprint::config{NeedCartonsForShipping}) {
			$$specs{alert} = 'Shipping requires that the project be packed in cartons.';
			$$specs{NeedPlainCartons} = 1;
			return 'uncalculated';
		}
		if ($$services{BulkSkids} and @{$$services{BulkSkids}}) {
			$carton_service_index = $$services{BulkSkids}[0];
		} # end if
	} else {
		$$specs{NeedPlainCartons} = 0;
	} # end if

	my $carton_specs;
	if ( $carton_service_index ) {
		my $carton_status = openprint::service::status( $project_index, $carton_service_index );
    $openprint::log->debug("Status of cartons is $carton_status") if DEBUG;
		if ( sets::isin( $carton_status,['', 'uncalculated'] ) ) {
			openprint::service::internal_calc( $log, $dbh, $variable, $project_index, $carton_service_index, 'Skids' );
		} # end if
    $carton_specs = openprint::service::get_specs_ref($Project, $carton_service_index);
	} # end if

	if ( ! $$specs{ToCity} ) {
		$$specs{alert} .= 'Please enter To city<br/>';
		#return $$specs{Status} = 'uncalculated';
	} # end if
	if ( !$$specs{ToStateProvince} ) {
		$$specs{alert} .= 'Please enter To State/Province<br/>';
		#return $$specs{Status} = 'uncalculated';
	} # end if
	if ( ! $$specs{ToCountry} ) {
		$$specs{alert} .= 'Please enter To Country<br/>';
		#return $$specs{Status} = 'uncalculated';
	} # end if
	my @shipping_services;
	foreach my $ServiceType ( openprint::ServiceType->find(category=>'Shipping') ) {
		next if ! $$services{$ServiceType->name()};
		foreach ( @{$$services{$ServiceType->name()}} ) {
			push @shipping_services, $_ if $_ != $service_index;
		} # end foreach
	} # end foreach ServiceType

	foreach my $qty_index ( $$specs{qty_index} ? $$specs{qty_index} : $Project->quantity_indexes() ) {
		$$specs{"txtPrice$qty_index"} =~ s/[^\-\.\d]//g if $$specs{"txtPrice$qty_index"};
		$$specs{"txtQuantity$qty_index"} =~ s/\D//g if $$specs{"txtQuantity$qty_index"};
		$$specs{"txtQuantity$qty_index"} = $Project->quantity($qty_index) if ! $$specs{"txtQuantity$qty_index"};
		if ( ! $$specs{"txtQuantity$qty_index"} ) {
			$log->debug('No qty');
		} # end if
		my $carton_qty_index = $$specs{qty_index} ? $Project->ordered_quantity_index() : $qty_index;

		if ( (!$$specs{'chkOverridePackageWeight'.$qty_index}) or ($$specs{'chkOverridePackageWeight'.$qty_index} ne 'Y') ) {
	# Load from skids or cartons
			$$specs{'txtPackageWeight'.$qty_index} = $$carton_specs{'txtPackageWeight'.$carton_qty_index};
		} # end if
		if ( $carton_service_index and ! $$carton_specs{'txtItemsPerPackage'.$carton_qty_index} ) {
			# XXX DEPRECATE
			if ( $$carton_specs{txtItemsPerPackage} ) {
				$$carton_specs{'txtItemsPerPackage'.$carton_qty_index} = $$carton_specs{txtItemsPerPackage};
			} else {
				$$specs{alert} = 'Unable to determine how many items per carton for qty '. $carton_qty_index;
			} # end if
		} # end if

		my $other_shipped_quantity = 0;
		foreach my $sid ( @shipping_services ) {
			my $service_specs = openprint::service::get_specs_ref( $Project, $sid );
			$other_shipped_quantity += $$service_specs{'txtQuantity'.$qty_index};
		} # end foreach sid
		$openprint::log->debug('Other Shipped Quantity: '.$other_shipped_quantity);

		if ( $$specs{'txtQuantity'.$qty_index} == $Project->quantity($qty_index) ) {
			$$specs{'txtQuantity'.$qty_index} = $Project->quantity($qty_index) - $other_shipped_quantity;
		} # end if

		if ( $other_shipped_quantity + $$specs{'txtQuantity'.$qty_index} > $Project->quantity( $qty_index ) ) {
			$$specs{alert} .= 'There are more items being shipped or picked up than are being produced. Please edit the quantities being shipped or picked up. Recommended amount: ' . ($Project->quantity($qty_index) - $other_shipped_quantity) . '<br/>';
			$status = 'uncalculated';
		} # end if

		my $items_per_package = 0;	
		if ( $$carton_specs{'txtItemsPerPackage'.$qty_index} ) {
			$items_per_package = $$carton_specs{'txtItemsPerPackage'.$qty_index};
		} else {
			$items_per_package = $$carton_specs{'txtItemsPerPackage'.$carton_qty_index};
		}
		if ( ! $items_per_package ) {
			$$specs{alert} .= "Unable to determine the # of items per package.<br/>";
			return $$specs{Status} = 'uncalculated';	
		}	

		if ( (!$$specs{chkOverridePackageQuantity}) or ( $$specs{chkOverridePackageQuantity} ne 'Y' ) ) {
			$$specs{'txtPackageQuantity'.$qty_index} = ceil( $$specs{'txtQuantity'.$qty_index}/$items_per_package );
		} # end if

		$$specs{"txtTotalWeight$qty_index"} = sprintf('%.2f', (int( $$specs{'txtQuantity'.$qty_index}/$items_per_package ) * $$specs{'txtPackageWeight'.$qty_index}) + (($$specs{'txtQuantity'.$qty_index} % $items_per_package ) * $$carton_specs{txtFinishedWeight}) );

		if ( ! $$specs{"OverridePrice$qty_index"} or $$specs{"OverridePrice$qty_index"} ne 'Y' ) {
			$$specs{"txtPrice$qty_index"} = 0;
		} # end if

		my $FromCountry = openprint::Location->find_one(type=>'country', short=>$$specs{FromCountry});
		$FromCountry = openprint::Location->find_one(type=>'country', name=>$$specs{FromCountry}) if ! $FromCountry;
		if ( $FromCountry ) {
			my $FromState = openprint::Location->find_one(type=>['state','province'], short=>$$specs{FromStateProvince});
			$FromState = openprint::Location->find_one(type=>['state','province'], name=>$$specs{FromStateProvince}) if ! $FromState;
			if ( $FromState ) {
				my $FromCity = openprint::Location->find_one(type=>'city', name=>$$specs{FromCity});

				if ( $FromCity ) {
					my $ToCountry = openprint::Location->find_one(type=>'country', short=>$$specs{ToCountry});
					$ToCountry = openprint::Location->find_one(type=>'country', name=>$$specs{ToCountry}) if ! $ToCountry;
					if ( $ToCountry ) {
						my $ToState = openprint::Location->find_one(type=>['state','province'], short=>$$specs{ToStateProvince});
						$ToState = openprint::Location->find_one(type=>['state','province'], name=>$$specs{ToStateProvince}) if ! $ToState;
						if ( $ToState ) {
							my $ToCity = openprint::Location->find_one(type=>'city', name=>$$specs{ToCity});

							if ( $ToCity ) {
								#my $service_name = join('',
                                            #'ShippingFrom', $FromCountry->name(), $FromState->name(), $FromCity->name(),
                                            #'To', $ToCountry->name(), $ToState->name(), $ToCity->name());
								my $service_name = join('',
                                            'ShippingFrom', $FromCity->name(), $FromState->name(), $FromCountry->name(), 
                                            'To', $ToCity->name(), $ToState->name(), $ToCountry->name() );
								$service_name =~ s/\s//g;

								my $MR_Service = openprint::Service->find_one( name=>$service_name.'MakeReady' );
								#my $MR_Service = openprint::Service->find_one( name=>join('', 'To', $ToCity->name(), $ToState->name(), $ToCountry->name(), 'MakeReady' );
								my $Service = openprint::Service->find_one( name=>join('', 
											'ShippingFrom', $FromCountry->name(), $FromState->name(), $FromCity->name(), 
											'To', $ToCountry->name(), $ToState->name(), $ToCity->name() ) );
								$Service = openprint::Service->find_one( name=>'Shipping' ) if ! $Service;

								$$specs{"hdnBreakdown$qty_index"} = '<table>';
								$$specs{"hdnBreakdown$qty_index"} .= '<tr><td colspan="2">'.join(' ', 'From', 
									join(', ', $FromCity->name(), $FromState->name(), $FromCountry->name() ),
									'To',
									join(', ', $ToCity->name(), $ToState->name(), $ToCountry->name() ),
								) . '</td></tr>';

								my @Equipment = openprint::Equipment->find( 'servicetype_id @>'=> $$Project_Service{servicetype_id} );

								my $bestPrice;
								foreach my $Equipment ( @Equipment ) {

									my $total;
									$$specs{"hdnBreakdown$qty_index"} .= '<tr><td colspan="2">On ' . $Equipment->name() . '</td></tr>';	
									if ( my $MinimumPackages = $Equipment->Specification( 'Minimum Packages' ) ) {
										if ( (!$$specs{'txtPackageQuantity'.$qty_index}) or ( $$MinimumPackages{value} > $$specs{'txtPackageQuantity'.$qty_index} ) ) {
											$$specs{"hdnBreakdown$qty_index"} .= '<tr><td class="error" colspan="2">Not enough ' . $$carton_specs{ServiceType} . ' minimum ' . $$MinimumPackages{value} . ' > ' . $$specs{'txtPackageQuantity'.$qty_index} . '</td></tr>';
											next;
										} # end if
									} # end if
									if ( $MR_Service ) {
										my $Price = $MR_Service->get_Price( undef, $Equipment );
										$total = $$Price{Price};
										$$specs{"hdnBreakdown$qty_index"} .= sprintf('<tr><td>MakeReady:</td><td class="Price">$%.2f</td></tr>', $$Price{Price} );
									} else {
										$openprint::log->debug("No MR Service found for ${service_name}MakeReady");
									} # end if
									if ( $Service ) {
										my $Price = $Service->get_Price( $$specs{'txtPackageQuantity'.$qty_index}, $Equipment );
										if ( $Price ) {
											if ( $$Price{units} eq 'per package' ) {
												$$Price{Total} = $$specs{'txtPackageQuantity'.$qty_index} * $$Price{Price};
												$total += $$Price{Total};
												$$specs{"hdnBreakdown$qty_index"} .= sprintf('<tr><td>%d %s * $%.2f%s =</td><td class="Price">$%.2f</td></tr>', 
														$$specs{'txtPackageQuantity'.$qty_index}, $$carton_specs{ServiceType}, @$Price{'Price','units','Total'} );
											} else {
												$log->error("unknown units on $$Service{name} $$Price{units}");
											} # end if
										} else {
											$openprint::log->debug('No price found for '.$service_name);
										} # end if
									} else {
										$openprint::log->debug('No service found for '.$service_name);
									} # end if Service
									$$specs{"hdnBreakdown$qty_index"} .= sprintf('<tr class="totals"><td></td><td class="Price">$%.2f</td></tr>', $total );
									$$specs{"hdnBreakdown$qty_index"} .= '</table>';
									if ( (!$bestPrice) or ( $$bestPrice{price} > $total ) ) {
										$$bestPrice{total} = $total;
										$$bestPrice{Equipment} = $Equipment;
									} # end if
								} # end foreach Equipment

								if ( $bestPrice ) {
									$$specs{"txtPrice$qty_index"} = $$bestPrice{total};
									$$specs{"Equipment$qty_index"} = $$bestPrice{Equipment}->id();
								} # end if
							} # end if ToCity
						} # end if ToState
					} # end if ToCoutnry
				} # end if FromCity
			} # end if FromState
		} # end if FromCountry

		if ( ! $$specs{"OverridePrice$qty_index"} or $$specs{"OverridePrice$qty_index"} ne 'Y' ) {
			$$specs{"txtPrice$qty_index"} = sprintf('%.2f', $$specs{"txtPrice$qty_index"});
		} # end if
	} # end foreach qty_index
	return $$specs{Status} = $status;
} # end sub calc

sub display {
	my ( $project_index, $service_index, $variable ) = @_;

	if ( ! ( $$variable{FromCity} and $$variable{FromPostalCode} and $$variable{FromStateProvince} and $$variable{FromCountry} ) ) {
$openprint::log->debug("Populating fields");
		my %shipping_fields = (
				FromCompanyName	=>	'CompanyName',
				FromAddress1		=>	'Address1',
				FromAddress2		=>	'Address2',
				FromCity			=>	'City',
				FromStateProvince	=>	'StateProvince',
				FromCountry		=>	'Country',
				FromPostalCode	=>	'PostalCode',
				FromPhone			=>	'Phone',
				FromExtension		=>	'Extension',
				FromFax			=>	'Fax',
				FromEmail			=>	'Email',
				);

		
		my $Company = new openprint::Company( $openprint::config{owner_id} );
		my $address = $Company->get_shipping_address();
		foreach my $k ( keys %shipping_fields ) {
			$$variable{$k} = $address->get( $shipping_fields{$k} ) if ! $$variable{$k};
		} # end foreach
		$$variable{FromCompanyName} = $Company->name() if ! $$variable{FromCompanyName};
		$$variable{FromCompanyAddress1} = $Company->address1() if ! $$variable{FromCompanyAddress1};
		$$variable{FromCompanyAddress2} = $Company->address2() if ! $$variable{FromCompanyAddress2};
		$$variable{FromCompanyCity} = $Company->city() if ! $$variable{FromCompanyCity};
		$$variable{FromCompanyStateProvince} = $Company->state() if ! $$variable{FromCompanyStateProvince};
		$$variable{FromCompanyCountry} = $Company->country() if ! $$variable{FromCompanyCountry};
		$$variable{FromCompanyPostalCode} = $Company->postalcode() if ! $$variable{FromCompanyPostalCode};
	} # end if

	if ( $openprint::session{company_id} and ( ! (
		$$variable{ToCity} and $$variable{ToPostalCode} and $$variable{ToStateProvince} and $$variable{ToCountry} ) ) ) {
		my %shipping_fields = (
				ToCompanyName		=>	'CompanyName',
				ToAddress1		=>	'Address1',
				ToAddress2		=>	'Address2',
				ToCity			=>	'City',
				ToStateProvince	=>	'StateProvince',
				ToCountry			=>	'Country',
				ToPostalCode		=>	'PostalCode',
				ToPhone			=>	'Phone',
				ToExtension		=>	'Extension',
				ToFax				=>	'Fax',
				ToEmail			=>	'Email',
				);

		my $Company = new openprint::Company( $openprint::session{company_id} );
		my $address = $Company->get_shipping_address();
		foreach my $k ( keys %shipping_fields ) {
			$$variable{$k} = $address->get( $shipping_fields{$k} ) if ! $$variable{$k};
		} # end foreach
		$$variable{ToCompanyName} = $Company->name() if ! $$variable{ToCompanyName};
		$$variable{ToCompanyAddress1} = $Company->address1() if ! $$variable{ToCompanyAddress1};
		$$variable{ToCompanyAddress2} = $Company->address2() if ! $$variable{ToCompanyAddress2};
		$$variable{ToCompanyCity} = $Company->city() if ! $$variable{ToCompanyCity};
		$$variable{ToCompanyStateProvince} = $Company->state() if ! $$variable{ToCompanyStateProvince};
		$$variable{ToCompanyCountry} = $Company->country() if ! $$variable{ToCompanyCountry};
		$$variable{ToCompanyPostalCode} = $Company->postalcode() if ! $$variable{ToCompanyPostalCode};
	} # end if

} # end sub display

sub summary {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;
	my $services = $Project->services();

	if ( $qty_index ) {
		if ( $qty_index eq 'Used' ) {
			my $packages = $$specs{txtPackageQuantityUsed} ? $$specs{txtPackageQuantityUsed} : $$specs{'txtPackageQuantity'.$Project->ordered_quantity_index()};
			if ( $$services{PlainCartons} ) {
				return sprintf( qq{%d items in %d carton%s\nWeighing %.2flbs}, 
					( $$specs{'txtQuantity'.$qty_index} ? $$specs{txtQuantityUsed} : $$specs{'txtQuantity'.$Project->ordered_quantity_index()} ),
					$packages, ( $packages==1?'' : 's'), 
					( $$specs{txtTotalWeightUsed} ? $$specs{txtTotalWeightUsed} : $$specs{'txtTotalWeight'.$Project->ordered_quantity_index()} ),
					);
			} else {
				return sprintf( qq{%d items in %d package%s\nWeighing %.2flbs}, 
					( $$specs{'txtQuantity'.$qty_index} ? $$specs{txtQuantityUsed} : $$specs{'txtQuantity'.$Project->ordered_quantity_index()} ),
					$packages, ( $packages==1?'' : 's'), 
					( $$specs{txtTotalWeightUsed} ? $$specs{txtTotalWeightUsed} : $$specs{'txtTotalWeight'.$Project->ordered_quantity_index()} ),
					);
			} # end if
		} else {
			if ( $$specs{'txtPackageQuantity'.$qty_index} ) {
				if ( $$services{PlainCartons} ) {
					return sprintf( qq{%d items in %d carton%s\nweighing %.2flbs}, @$specs{'txtQuantity'.$qty_index,'txtPackageQuantity'.$qty_index},( $$specs{'txtPackageQuantity'.$qty_index}==1?'' : 's'), $$specs{'txtTotalWeight'.$qty_index} );
				} else {
					return sprintf( qq{%d items in %d package%s\nweighing %.2flbs}, @$specs{'txtQuantity'.$qty_index,'txtPackageQuantity'.$qty_index},( $$specs{'txtPackageQuantity'.$qty_index}==1?'' : 's'), $$specs{'txtTotalWeight'.$qty_index} );
				} # end if
			} elsif ( $$specs{'txtQuantity'.$qty_index} ) {
				return sprintf( q{%d items}, $$specs{'txtQuantity'.$qty_index} ) if $$specs{"txtPrice$qty_index"};
			} else {
				return 'none';
			} # end if
		} # end if Used or index
	} else {
		my $html = '';

		if ( $$specs{FromAddress1} or $$specs{FromCity} or $$specs{FromStateProvince} or $$specs{FromCountry} ) {
			$html .= 'From: '.from( $specs ).'<br/>';
		} # end if
		if ( $$specs{ToAddress1} or $$specs{ToCity} or $$specs{ToStateProvince} or $$specs{ToCountry} ) {
			$html .= 'To: ' . to($specs).'<br/>';
		} # end if
		if ( ! $html ) {
			return 'unspecified address';
		} # end if
		return $html;
	} # end if
	return;
} # end sub summary

sub from {
	my ( $specs ) = @_;
	return join("\n", 
			( $$specs{FromCompanyName} ? $$specs{FromCompanyName} : () ),
			join(', ', map { $_ ? $_ : () } ( $$specs{FromAddress1} , $$specs{FromAddress2},
				@$specs{'FromCity','FromStateProvince','FromCountry'},
				@$specs{FromPostalCode} ) ),
			);
} # end sub from
sub to {
	my ( $specs ) = @_;
	return join("\n", 
			( $$specs{ToCompanyName} ? $$specs{ToCompanyName} : () ),
			join(', ', map { $_ ? $_ : () } ( $$specs{ToAddress1}, $$specs{ToAddress2},
				@$specs{'ToCity','ToStateProvince','ToCountry'},
				@$specs{ToPostalCode} ) ),
			);
} # end sub to

sub save {
	my ( $p_id, $s_id, $param ) = @_;
    my $Project = new openprint::Project( $p_id );

	if ( 1 ) {
		my $Location = openprint::Location->find_one( company_id=>$Project->company_id() );
		
	} # end if
} # end sub save

sub setup_defaults {
	my ( $Project, $Service ) = @_;
	my %defaults;

	$defaults{to_company_id} = $openprint::config{owner};
	$defaults{from_company_id} = $Project->company_id();
	return %defaults;
} # end sub setup_defaults

1;
__END__
