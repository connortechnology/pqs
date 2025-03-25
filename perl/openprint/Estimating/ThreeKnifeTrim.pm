package openprint::Estimating::ThreeKnifeTrim;
use strict;

require openprint::service;
use POSIX           qw(ceil);

use constant DEBUG => 0;

use vars qw( %ServicePrices );
%ServicePrices = (
  ThreeKnifeTrimMakeReady => {
    units => [],
    range_units => [],
  },
  'ThreeKnifeTrim(\d+)Sides' => {
    units => [ 'per m', 'each' ],
    range_units => ['caliper'],
    },
  ThreeKnifeTrim => {
    units => [ 'per m', 'each' ],
    range_units => ['caliper'],
    },
  );


my %variables = (
	'Sides' => ['save'],
	'ddmEquipment1' => ['save','output'], 'ddmEquipment2' => ['save','output'], 'ddmEquipment3' => ['save','output'],
	'OverridePrice1' => ['save'], 'OverridePrice2' => ['save'], 'OverridePrice3' => ['save'],
	'txtPrice1' => ['save','output'], 'txtPrice2' => ['save','output'], 'txtPrice3' => ['save','output'],
	'Markup1'	=> ['save'], 'Markup2'	=> ['save'], 'Markup3'	=> ['save'],
	'txtQuantity1' => ['save'], 'txtQuantity2' => ['save'], 'txtQuantity3' => ['save'],
);
sub variables {
    my @v;
    foreach my $k ( keys %variables ) {
        push @v, $k if sets::isin( 'save', $variables{$k} );
    } # end foreach;
    return @v;
}

sub no_outputs {
    my @v;
    foreach my $k ( keys %variables ) {
        push @v, $k if ! sets::isin( 'output', $variables{$k} );
    } # end foreach;
    return @v;
} # end sub no_outputs

# A function that is smart enough to return true if the project needs folding, and false if it doesn't.
sub neccessary {
	my ( $Project ) = @_;

	my $services = $Project->services();

	if ( $$services{NoBindery} ) {
		$openprint::log->debug(" ** Project is marked as No bindery, ThreeKnifeTrim not needed ! ** ");
		return 0;
	} # end if
	return 0 if ! openprint::ServiceType->find_one(type=>'ThreeKnifeTrime');

	my $printing_service_index = $$services{''}[0] if $$services{''};
	my $specs = openprint::service::get_specs_ref( $Project, $printing_service_index );
	if ( sets::isin( $$specs{rdbTemplateType},[ 'SpinePasting','Unbound','NoBindery'] ) ) {
		return 1;
	} # end if

	return 0;
} # end sub neccessary

sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $specs) = @_;

	my $Project = new openprint::Project( $pid );

	$$specs{Sides} =~ s/\D//g;
	if ( ! $$specs{Sides} ) {
		$$specs{alert} = 'Please enter the # of sides to be trimmed.';
		return $$specs{Status} = 'uncalculated';
	} # end if

	my @Equipment = openprint::Equipment->find('Specifications'=>{'ThreeKnifeTrim Capable'=>'Y'},'useinestimating'=>1);
	if ( ! @Equipment ) {
		$$specs{alert} = 'We have no three knife trimmers.';
		return $$specs{Status} = 'uncalculated';
	} # end if

	my $services = $Project->services();
	my $project_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] ) if $$services{''};
	my $finished_calliper = $Project->calliper( );

	my $status = 'calculated';

	foreach my $qty_index ( $Project->quantity_indexes() ) {
		$$specs{'Markup'.$qty_index} =~ s/[^\d\.\-]//g;
		$$specs{'txtPrice'.$qty_index} =~ s/[^\d\.]//g;
		$$specs{'txtQuantity'.$qty_index} =~ s/[^\d\.]//g;
		$$specs{'txtQuantity'.$qty_index} = $Project->quantity( $qty_index ) if ! $$specs{'txtQuantity'.$qty_index};
		next if ! $$specs{'txtQuantity'.$qty_index};

		my %BestPrice;

		foreach my $Equipment ( @Equipment ) {
			$$specs{'hdnBreakdown'.$qty_index} .= '<fieldset><legend>'.$Equipment->name().'</legend>';

			my $total = 0;

			my %MakeReady = openprint::service::get_price_object('ThreeKnifeTrimMakeReady', $$specs{Sides}, $Equipment );
			if ( ! %MakeReady ) {
				$$specs{'hdnBreakdown'.$qty_index} .= 'No MakeReady price.<br/>';
			} else {
				$$specs{'hdnBreakdown'.$qty_index} .= sprintf('MakeReady Price: $%1$.2f%2$s<br/>', @MakeReady{'Price','units'} );
				$total += $MakeReady{Price};
			} # end if

			my %ServicePrice = openprint::service::get_price_object( 'ThreeKnifeTrim'.$$specs{Sides}.'Sides', $finished_calliper, $Equipment ); 
			if ( ! %ServicePrice ) {
				%ServicePrice = openprint::service::get_price_object( 'ThreeKnifeTrim', $finished_calliper, $Equipment ); 
			} # end if

			if ( ! %ServicePrice ) {
				$$specs{'hdnBreakdown'.$qty_index} .= 'No Service price.<br/>';
			} elsif ( lc $ServicePrice{units} eq 'per m' ) {
				$ServicePrice{Total} += $ServicePrice{Price} * $$specs{'txtQuantity'.$qty_index} / 1000;
			} else {
				$ServicePrice{Total} += $ServicePrice{Price} * $$specs{'txtQuantity'.$qty_index};
			} # end if
			$total += $ServicePrice{Total};
			$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Service Price: $%1$.2f%2$s = $%3$.2f<br/>', @ServicePrice{'Price','units','Total'} );

			if ( my $minimumcharge = openprint::service::get_price('ThreeKnifeTrimMinimumCharge', undef, $Equipment ) ) {
				$total = $minimumcharge if $total < $minimumcharge;
			} # end if
			$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Total: $%.2f<br/>', $total );
			
			if ( ( ! defined $BestPrice{Total} ) or $total < $BestPrice{Total} ) {
				$BestPrice{Total} = $total;
				$BestPrice{Equipment} = $Equipment;
				$BestPrice{ServicePrice} = \%ServicePrice;
			} # end if
			$$specs{'hdnBreakdown'.$qty_index} .= '</fieldset>';
        } # end foreach Equipment

		if ( ! defined $BestPrice{Total} ) {
			$status = 'uncalculated';
		} else {
			$$specs{'ddmEquipment'.$qty_index} = $BestPrice{Equipment}->id();
		} # end if

        $$specs{'txtUnitPrice'.$qty_index} = sprintf($openprint::config{UnitPriceFormat}, ( ($BestPrice{ServicePrice}{'Total'} + $BestPrice{'LastServicePrice'}{'Total'} ) / $$specs{'txtQuantity'.$qty_index} ) * (1+$Project->markup()/100) );
		if ( $$specs{'OverridePrice'.$qty_index} ne 'Y' ) {
			$$specs{'txtPrice'.$qty_index} = sprintf( $openprint::config{ProjectMoneyFormat}, $BestPrice{Total} * (1+$$specs{"Markup$qty_index"}/100) * (1+$Project->markup()/100) );
		} else {
			$$specs{'txtPrice'.$qty_index} = sprintf( $openprint::config{ProjectMoneyFormat}, $$specs{'txtPrice'.$qty_index} );
		} # end if

    } # end foreach qty_index
    return $status;
} # end sub calc

sub summary {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;

	if ( $qty_index ) {
		if ( $$specs{'ddmEquipment'.$qty_index} ) {
			my $Equipment = new openprint::Equipment( $$specs{'ddmEquipment'.$qty_index} );
			return ' on ' . $Equipment->name();
		} # end if
		return '';
	} # end if
	$specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;

	return $$specs{Sides} . 'side' . ($$specs{Sides} == 1 ? '' : 's');
} # end sub summary

sub display {
	my ( $log, $dbh, $variable, $project_index, $service_index ) = @_;

	@{$$variable{Equipment}} = openprint::Equipment->find( 
			Specifications	=>	{'ThreeKnifeTrim Capable'=>'Y'},
			useinestimating	=>	1,
			order				=>	'lower(strName)'
			);
$openprint::log->warn("ThreeKnifeTrim Equipment: " . @{$$variable{Equipment}} );
} # end sub display

1;
__END__
