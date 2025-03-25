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

package openprint::Estimating::CanadaPost;
use strict;

require Business::CanadaPost;
require openprint::service;
require openprint::Project;
require openprint::Estimating::Shipping;

use vars qw( $log $dbh %variable %config %session );
*variable = \%openprint::variable;
*session = \%openprint::session;
*config = \%openprint::config;
*log = \$openprint::log;
*dbh = \$openprint::dbh;

use constant DEBUG => 0;

my %variables = (
	'txtQuantity1'=>['save','output'], 'txtQuantity2'=>['save','output'], 'txtQuantity3'=>['save','output'],
	'txtPrice1'=>['save','output'], 'txtPrice2'=>['save','output'], 'txtPrice3'=>['save','output'],
	'txtPackageQuantity1'=>['save','output'], 'txtPackageQuantity2'=>['save','output'], 'txtPackageQuantity3'=>['save','output'],
	'chkOverridePackageQuantity'=>['save'],
	'txtTotalWeight1'=>['save','output'], 'txtTotalWeight2'=>['save','output'], 'txtTotalWeight3'=>['save','output'],
	'txtPackageWeight'=>['save','output'],
	'ddmServiceType'=>['save','output'],
	'alert'=>['save','output'],'Status'=>['output'],
	'FromCompany'=>['save'],'FromAddress1'=>['save'],'FromAddress2'=>['save'],'FromCity'=>['save'],'FromStateProvince'=>['save'],'FromCountry'=>['save'],'FromPostalCode'=>['save'],'FromPhone'=>['save'],'FromFax'=>['save'],'FromEmail'=>['save'],
	'ToCompany'=>['save'],'ToAddress1'=>['save'],'ToAddress2'=>['save'],'ToCity'=>['save'],'ToStateProvince'=>['save'],'ToCountry'=>['save'],'ToPostalCode'=>['save'],'ToPhone'=>['save'],'ToFax'=>['save'],'ToEmail'=>['save'],
	'ServiceTypeDiv'=>['output'],
	'hdnBreakdown1'=>['output'], 'hdnBreakdown2'=>['output'], 'hdnBreakdown3'=>['output'],
	'NeedPlainCartons'=>['output'],
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

sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

	my $status = 'calculated';
	$$specs{alert} = '';

	@$specs{'txtPrice1','txtPrice2','txtPrice3'} = ('','','');

	my $Project = new openprint::Project( $project_index );
	my $services = $Project->services();

    if ( ! ( $$services{PlainCartons} and @{$$services{PlainCartons}} ) ) {
        $$specs{alert} = 'Canada Post Shipping requires that the project be packed in cartons.';
        $$specs{NeedPlainCartons} = 1;
        return $$specs{Status} = 'uncalculated';
    } else {
        $$specs{NeedPlainCartons} = 0;
    } # end if

	my $carton_status = openprint::service::status( $Project->id(), $$services{PlainCartons}[0] );
	my $carton_specs;
$log->debug("Carton Status: $carton_status");
	if ( sets::isin( $carton_status, ['', 'uncalculated' ] ) ) {
		$carton_specs = openprint::service::internal_calc( $log, $dbh, \%variable, $Project->id(), $$services{PlainCartons}[0], 'Skids' );
	} else {
		$carton_specs = openprint::service::get_specs_ref( $Project, $$services{PlainCartons}[0] );
	} # end if

	foreach my $qty_index ( $Project->quantity_indexes() ) {
		if ( ! $$carton_specs{"txtItemsPerPackage$qty_index"} ) {
			$$specs{alert} .= "Unable to determine the number of items in each package for quantity $qty_index.";
		} # end if
	} # end foreach

	if ( $$specs{alert} ) {
$log->debug($$specs{alert});
		return $$specs{Status} = 'uncalculated';
	} # end if
$log->debug("Shiprequest 1");


	$$specs{ToPostalCode} =~ s/[^0-9A-Za-z]//g;
	if ( ! $$specs{ToPostalCode} ) {
		$$specs{alert} = 'Please enter your postal code.';
		return $$specs{Status} = 'uncalculated';
	} elsif ( length $$specs{ToPostalCode} < 4 ) {
		$$specs{alert} = 'Invalid Postal/ZIP Code.';
		return $$specs{Status} = 'uncalculated';
	} # end if

if ( 0 ) {
	my $Supplier = openprint::Company->find_one( supplier=>'Y', order=>'id');
	if ( $Supplier ) {
		my %shipping_fields = (
				FromCity			=>	'City',
				FromStateProvince	=>	'StateProvince',
				FromCountry			=>	'Country',
				FromPostalCode		=>	'PostalCode',
				);
		@$specs{ keys %shipping_fields } = $Supplier->load_shipping( @shipping_fields{ keys %shipping_fields } );
		$$specs{FromCity} = $Supplier->city() if ! $$specs{FromCity};
		$$specs{FromStateProvince} = $Supplier->state() if ! $$specs{FromStateProvince};
		$$specs{FromCountry} = $Supplier->country() if ! $$specs{FromCountry};
		$$specs{FromPostalCode} = $Supplier->postalcode() if ! $$specs{ShipperPostalCode};
	} else {
$log->debug("No supplier");
	} # end if
} # end if

	if ( ! $config{CanadaPost_MerchantID} ) {
		$$specs{alert} .= "You have not configured your Canada Post Merchant ID";
		return $$specs{Status} = 'uncalculated';
	}
$log->debug("Shiprequest ");
	my $shiprequest = Business::CanadaPost->new(
			merchantid => $config{CanadaPost_MerchantID},
			frompostal =>  $$specs{FromPostalCode},
			testing    => 1,
			units		=>	'imperial',
			language	=>	'en',
		);
$log->debug("Shiprequest $shiprequest");

	# Try to auto-fill as many of the ShipTo fields as we can
	if ( ! ( $$specs{ToPostalCode} and $$specs{ToCity} and $$specs{ToStateProvince} and $$specs{ToCountry} ) ) {

		# If we are logged in, try to load from shipping, then from basic data
		if ( $session{company_id} ) {
			$$specs{ShipToCity} = $openprint::Company->city() if ! $$specs{ShipToCity};
			$$specs{ShipToStateProvince} = $openprint::Company->state() if ! $$specs{ShipToStateProvince};
			$$specs{ShipToCountry} = $openprint::Company->country() if ! $$specs{ShipToCountry};
			$$specs{ShipToPostalCode} = $openprint::Company->postalcode() if ! $$specs{ShipToPostalCode};
		} # end if

		$$specs{ShipToCountry} = $session{Country} if ! $$specs{ShipToCountry};
	} # end if
	$shiprequest->setcountry($$specs{ToCountry});
	$shiprequest->setprovstate($$specs{ToStateProvince});
	$shiprequest->settopostalzip($$specs{ToPostalCode});
	$shiprequest->settocity($$specs{ToCity});

	foreach my $qty_index ( $Project->quantity_indexes() ) {
		$$specs{"txtQuantity$qty_index"} = $Project->quantity($qty_index) if ! $$specs{"txtQuantity$qty_index"};
		next if ! $$specs{"txtQuantity$qty_index"};
		$shiprequest->settotalprice( $Project->price( $qty_index ) );

		$$specs{'hdnBreakdown'.$qty_index} = '';
		if ( $$specs{chkOverridePackageWeight} ne 'Y' ) {
			$$specs{"txtPackageWeight$qty_index"} = $$carton_specs{"txtPackageWeight$qty_index"};
			$log->debug("Package weight: " . $$specs{"txtPackageWeight$qty_index"});
		}
		if ( $$specs{chkOverridePackageQuantity} ne 'Y' ) {
			$$specs{"txtPackageQuantity$qty_index"} = $$carton_specs{"txtPackageQuantity$qty_index"};
			my $full_cartons = int ( $$specs{'txtQuantity'.$qty_index} / $$carton_specs{"txtItemsPerPackage$qty_index"} );
			my $remaining = $$specs{'txtQuantity'.$qty_index} % $$carton_specs{"txtItemsPerPackage$qty_index"};
			my $last_package_weight = $remaining * $$carton_specs{txtFinishedWeight};

			my $Carton = new openprint::Material( $$carton_specs{"ddmPackageType$qty_index"} ) if $$carton_specs{"ddmPackageType$qty_index"};

			if ( $$specs{"txtPackageQuantity$qty_index"} > 1 ) {
# Go Shopping
				my %item = (
						( $_ = $Carton->specification('Width') ? ( width => $_ ) : () ),
						( $_ = $Carton->specification('Height') ? ( height => $_ ) : () ),
						( $_ = $Carton->specification('Depth') ? ( length => $_ ) : () ),
						( $_ = $Carton->specification('Length') ? ( length => $_ ) : () ),
						quantity	=>	$$specs{"txtPackageQuantity$qty_index"} -1,
						weight		=>	$$specs{txtPackageWeight},
						description	=>	$Project->Type()->description(),
						readytoship	=>	1
						);
				if ( !  $shiprequest->additem( %item ) ) {
					$$specs{alert} .= $shiprequest->geterror();
				}
				$log->debug("Adding " . join(',', map { join(' => ', $_, $item{$_} ) } keys %item ) . ' ' . $$specs{alert} );

			}
			my %item = (
					width =>  $Carton->specification('Width'),
					height => $Carton->specification('Height'),
					length => $Carton->specification('Depth'),
					quantity	=>	1,
					weight		=>	$last_package_weight,
					description	=>	$Project->Type()->description(),
					readytoship	=>	1,
					);
			if ( ! $shiprequest->additem( %item ) ) {
				$$specs{alert} .= $shiprequest->geterror();
			}
			$log->debug("Adding " . join(',', map { join(' => ', $_, $item{$_} ) } keys %item ) . ' in ' . $Carton->name() . ' ' . $$specs{alert} );

			$$specs{"txtTotalWeight$qty_index"} = ( $full_cartons * $$specs{txtPackageWeight} ) + $last_package_weight;
		} else {
			$$specs{"txtTotalWeight$qty_index"} = $$specs{txtPackageWeight} * $$specs{"txtPackageQuantity$qty_index"};
		} # end if

		#my $xml = $shiprequest->buildXML();
		#$log->debug("do getrequest $xml" . $shiprequest->geterror());
		if ( ! $shiprequest->getrequest() ) {
			$log->error("Failed sending request: " .$shiprequest->geterror() );
			$$specs{alert} = $shiprequest->geterror();
			return $$specs{Status} = 'uncalculated';
		} else {
			$log->debug("There are " . $shiprequest->getoptioncount() . " available shipping methods.");
		}

		my %bestService;
		my %rated_services;
		foreach my $i ( 1 .. $shiprequest->getoptioncount() ) {
			my $service = $shiprequest->getshipname( $i );
			my $price = $shiprequest->getshiprate( $i );

			if ( $$specs{"ddmServiceType$qty_index"} ) {
				if ( $$specs{"ddmServiceType$qty_index"} == $service ) {
					$bestService{Price} = $price;
					$bestService{Service} = $service;
				} # end if
			} else {
				if ( ( ! $bestService{Price} ) or ( $price < $bestService{Price} ) ) {
					$bestService{Price} = $price;
					$bestService{Service} = $service;
				} # end if
			} # end if
			$rated_services{$service} = $price;
		} # end while
		if ( ! $$specs{"ddmServiceType$qty_index"} ) {
			$log->debug("Choosing	$bestService{Service} as the ServiceType") if DEBUG;
			$$specs{"ddmServiceType$qty_index"} = $bestService{Service};
		} # end if
		$$specs{"ServiceTypeDiv$qty_index"} = qq{<select name="ddmServiceType$qty_index" onchange="calc(this.form.name);"><option value=""> Select </option>};
		$$specs{"ServiceTypeDiv$qty_index"} .= ssi::make_drop_down( [ map { $_, $_ } keys %rated_services ], $$specs{"ddmServiceType$qty_index"} );
		$$specs{"ServiceTypeDiv$qty_index"} .= '</select>';

		if ( $$specs{"ddmServiceType$qty_index"} ) {
			my %ServicePrice = openprint::service::get_price_object( 'Canada Post Shipping', $bestService{Price}, undef );
			if ( $ServicePrice{Price} > 0 ) {
				$ServicePrice{Total} = $ServicePrice{Price};
			} else {
				$ServicePrice{Total} = $bestService{Price} * (1 + $ServicePrice{Markup}/100);
			} # end if
			if ( $Project->markup() ) {
				$ServicePrice{Total} *= (1+$Project->markup()/100);
			}

			$$specs{"txtPrice$qty_index"} = Math::Round::nearest( 0.01, $ServicePrice{Total} );
		} # end if pickuptype and servicetype

	} # end foreach qty_index

	$log->debug("Canada Post!!!!!!!!!!!!!!!!!!");
	return $$specs{Status} = $status;
} # end sub calc

sub display {
	my ( $project_index, $service_index, $variable ) = @_;

	my $Project = new openprint::Project( $project_index );
	$$variable{Mode} = $Project->mode();
	openprint::Estimating::Shipping::display( @_ );

} # end sub display

sub summary {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;
	if ( $qty_index ) {
		return openprint::Estimating::Shipping::summary( @_ );
	} 
	my $html;
	$html .= $$specs{ddmServiceType}. "\n";
	$html .= openprint::Estimating::Shipping::summary( @_ );
	return $html;
} # end sub summary

sub save {
} # end sub save

1;
__END__
