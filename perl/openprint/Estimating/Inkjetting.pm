package openprint::Estimating::Inkjetting;
use strict;

require openprint::service;
require sets;

use constant DEBUG => 0;

my %variables = (
	'Quantity' => ['save'],
	'chkOverrideEquipment1'	=> ['save'], 'chkOverrideEquipment2'	=> ['save'], 'chkOverrideEquipment3'	=> ['save'],
	'ddmEquipment1' => ['save','output'], 'ddmEquipment2' => ['save','output'], 'ddmEquipment3' => ['save','output'],
	'OverridePrice1' => ['save'], 'OverridePrice2' => ['save'], 'OverridePrice3' => ['save'],
	'Markup1' => ['save'], 'Markup2' => ['save'], 'Markup3' => ['save'],
	'txtPrice1' => ['save','output'], 'txtPrice2' => ['save','output'], 'txtPrice3' => ['save','output'],
	'txtQuantity1' => ['save'], 'txtQuantity2' => ['save'], 'txtQuantity3' => ['save'],
	'Colours' => ['save'],
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
}

sub neccessary {
	my ( $Project ) = @_;

	#my $services = $Project->services( );
	#if ( $$services{''} ) {
		#my $project_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] );
		#return 1 if $$project_specs{'InkjettingQuantity'};
	#} # end if
	return 0;
} # end sub neccessary

sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $specs) = @_;

	my $Project = new openprint::Project( $pid );
	my $services = $Project->services();
	my $project_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] ) if $$services{''};

	$$specs{'Colours'} =~ s/\D//g;
	if ( ! $$specs{'Colours'} ) {
		$$specs{'alert'} = 'Please enter the number of colours.';
		return $$specs{'Status'} = 'uncalculated';
	} # end if

	my @Equipment = openprint::Equipment->find('Specifications'=>{'Inkjetting Capable'=>'Y'},'useinestimating'=>1);
	push @Equipment, openprint::Equipment->find('Specifications'=>{'Inkjetting Capable'=>'When PerfectBound'},'useinestimating'=>1) if $$services{'PerfectBind'};
	push @Equipment, openprint::Equipment->find('Specifications'=>{'Inkjetting Capable'=>'When Stitching'},'useinestimating'=>1) if $$services{'SaddleStitching'} or $$services{'LoopStitching'};
	if ( ! @Equipment ) {
		$$specs{'alert'} = 'We have no equipment for inkjetting.';
		return $$specs{'Status'} = 'uncalculated';
	} # end if

	my $status = 'calculated';

	foreach my $qty_index ( $Project->quantity_indexes() ) {
		$$specs{'txtPrice'.$qty_index} =~ s/[^\d\.]//g;
		$$specs{'Markup'.$qty_index} =~ s/[^\d\.\-]//g;
		$$specs{'txtQuantity'.$qty_index} =~ s/[^\d\.]//g;
		$$specs{'txtQuantity'.$qty_index} = $Project->quantity( $qty_index ) if ! $$specs{'txtQuantity'.$qty_index};
		next if ! $$specs{'txtQuantity'.$qty_index};

		my %BestPrice;
		$$specs{'hdnBreakdown'.$qty_index} = '';

		my @my_equipment;
		if ( $$specs{'chkOverrideEquipment'.$qty_index} eq 'Y' ) {
			@my_equipment = ( new openprint::Equipment( $$specs{'ddmEquipment'.$qty_index} ) );
		} else {
			@my_equipment = @Equipment;
		} # end if

		foreach my $Equipment ( @my_equipment ) {
			$$specs{'hdnBreakdown'.$qty_index} .= '<fieldset><legend>'.$Equipment->name().'</legend>';
			my $total = 0;

			my %MakeReady = openprint::service::get_price_object('InkjettingColourMakeReady', $$specs{'Colours'}, $Equipment );
			if ( ! %MakeReady ) {
				$$specs{'hdnBreakdown'.$qty_index} .= 'No MakeReady price.<br/>';
			} elsif ( lc $MakeReady{'units'} eq 'per colour' ) {
				$MakeReady{'Total'} = $MakeReady{'Price'} * $$specs{'Colours'};
				$total += $MakeReady{'Total'};
				$$specs{'hdnBreakdown'.$qty_index} .= sprintf('MakeReady Price: $%1$.2f%2$s * %4$d=$%3$.2f<br/>', @MakeReady{'Price','units','Total'}, $$specs{'Colours'} );
			} else {
				$$specs{'hdnBreakdown'.$qty_index} .= 'Unknown units on MakeReady price.<br/>';
			} # end if

			my %ServicePrice = openprint::service::get_price_object('Inkjetting', $$specs{'txtQuantity'.$qty_index}, $Equipment ); 
			if ( ! %ServicePrice ) {
				$$specs{'hdnBreakdown'.$qty_index} .= 'No Service price.<br/>';
			} elsif ( lc $ServicePrice{'units'} eq 'per m' ) {
				$ServicePrice{'Total'} += $ServicePrice{'Price'} * $$specs{'txtQuantity'.$qty_index} / 1000;
				$total += $ServicePrice{'Total'};
				$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Service Price: $%1$.2f%2$s * %4$d = $%3$.2f<br/>', @ServicePrice{'Price','units','Total'}, $$specs{'txtQuantity'.$qty_index} );
			} elsif ( lc $ServicePrice{'units'} eq 'each' ) {
				$ServicePrice{'Total'} += $ServicePrice{'Price'} * $$specs{'txtQuantity'.$qty_index};
				$total += $ServicePrice{'Total'};
				$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Service Price: $%1$.2f%2$s * %4$d = $%3$.2f<br/>', @ServicePrice{'Price','units','Total'}, $$specs{'txtQuantity'.$qty_index} );
			} else {
				$$specs{'hdnBreakdown'.$qty_index} .= 'Unknown units on Service price.<br/>';
			} # end if

			my %DataLoadPrice = openprint::service::get_price_object('InkjettingDataLoading', undef, $Equipment ); 
			if ( ! %DataLoadPrice ) {
				$$specs{'hdnBreakdown'.$qty_index} .= 'No Data Loading price.<br/>';
			} elsif ( lc $DataLoadPrice{'units'} eq 'per m' ) {
				$DataLoadPrice{'Total'} += $DataLoadPrice{'Price'} * $$specs{'txtQuantity'.$qty_index} / 1000;
				$total += $DataLoadPrice{'Total'};
				$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Data Loading Price: $%1$.2f%2$s * %4$d = $%3$.2f<br/>', @DataLoadPrice{'Price','units','Total'}, $$specs{'txtQuantity'.$qty_index} );
			} elsif ( lc $DataLoadPrice{'units'} eq 'each' ) {
				$DataLoadPrice{'Total'} += $DataLoadPrice{'Price'} * $$specs{'txtQuantity'.$qty_index};
				$total += $DataLoadPrice{'Total'};
				$$specs{'hdnBreakdown'.$qty_index} .= sprintf('DataLoading Price: $%1$.2f%2$s * %4$d = $%3$.2f<br/>', @DataLoadPrice{'Price','units','Total'}, $$specs{'txtQuantity'.$qty_index} );
			} else {
				$$specs{'hdnBreakdown'.$qty_index} .= 'Unknown units on Data Loading price.<br/>';
			} # end if

			my %DataProcessingPrice = openprint::service::get_price_object('InkjettingDataProcessing', undef, $Equipment ); 
			if ( ! %DataProcessingPrice ) {
				$$specs{'hdnBreakdown'.$qty_index} .= 'No Data Processing price.<br/>';
			} elsif ( lc $DataProcessingPrice{'units'} eq 'per m' ) {
				$DataProcessingPrice{'Total'} += $DataProcessingPrice{'Price'} * $$specs{'txtQuantity'.$qty_index} / 1000;
				$total += $DataProcessingPrice{'Total'};
				$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Data Processing Price: $%1$.2f%2$s * %4$d = $%3$.2f<br/>', @DataProcessingPrice{'Price','units','Total'}, $$specs{'txtQuantity'.$qty_index} );
			} elsif ( lc $DataProcessingPrice{'units'} eq 'each' ) {
				$DataProcessingPrice{'Total'} += $DataProcessingPrice{'Price'} * $$specs{'txtQuantity'.$qty_index};
				$total += $DataProcessingPrice{'Total'};
				$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Data Processing Price: $%1$.2f%2$s * %4$d = $%3$.2f<br/>', @DataProcessingPrice{'Price','units','Total'}, $$specs{'txtQuantity'.$qty_index} );
			} else {
				$$specs{'hdnBreakdown'.$qty_index} .= 'Unknown units on Data Processing price.<br/>';
			} # end if

			if ( my $minimumcharge = openprint::service::get_price('InkjettingMinimumCharge', undef, $Equipment ) ) {
				$total = $minimumcharge if $total < $minimumcharge;
			} # end if
			$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Total: $%.2f<br/>', $total );
			
			if ( ( ! defined $BestPrice{'Total'} ) or $total < $BestPrice{'Total'} ) {
				$BestPrice{'Total'} = $total;
				$BestPrice{'Equipment'} = $Equipment;
				$BestPrice{'ServicePrice'} = \%ServicePrice;
			} # end if
			$$specs{'hdnBreakdown'.$qty_index} .= '</fieldset>';
        } # end foreach Equipment

		if ( ! defined $BestPrice{'Total'} ) {
			$status = 'uncalculated';
		} else {
			$$specs{'ddmEquipment'.$qty_index} = $BestPrice{'Equipment'}->id();
		} # end if

		$$specs{'txtUnitPrice'.$qty_index} = sprintf($openprint::config{'UnitPriceFormat'}, 
				( $BestPrice{'ServicePrice'}{'Total'} / $$specs{'txtQuantity'.$qty_index} ) * (1+$Project->markup()/100) );
		if ( $$specs{'OverridePrice'.$qty_index} ne 'Y' ) {
			$$specs{'txtPrice'.$qty_index} = sprintf( $openprint::config{'ProjectMoneyFormat'}, 
					$BestPrice{'Total'}*(1+$$specs{"Markup$qty_index"}/100) * (1+$Project->markup()/100) );
		} else {
			$$specs{'txtPrice'.$qty_index} = sprintf( $openprint::config{'ProjectMoneyFormat'}, $$specs{'txtPrice'.$qty_index} );
		} # end if

    } # end foreach qty_index
    return $status;
} # end sub calc

sub summary {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;

	$specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;
	if ( $qty_index ) {
		if ( $$specs{'ddmEquipment'.$qty_index} ) {
			my $Equipment = new openprint::Equipment( $$specs{'ddmEquipment'.$qty_index} );
			return ' on ' . $Equipment->name();
		} # end if
		return '';
	} # end if

	return sprintf( '%d colour%s', $$specs{'Colours'}, $$specs{'Colours'} == 1 ? '' : 's' );
} # end sub summary

sub display {
	my ( $log, $dbh, $variable, $project_index, $service_index ) = @_;

	my $Project = new openprint::Project( $project_index );
	my $services = $Project->services();
	my @possible_equipment = openprint::Equipment->find( 'Specifications' => {'Inkjetting Capable'=>'Y'}, 'useinestimating'=>1,'order'=>'lower(strName)');
$openprint::log->debug("Equipment: @possible_equipment");
	push @possible_equipment, openprint::Equipment->find( 'Specifications' => {'Inkjetting Capable'=>'When Stitching'}, 'useinestimating'=>1,'order'=>'lower(strName)') if $$services{'SaddleStitching'} or $$services{'LoopStitching'};
	push @possible_equipment, openprint::Equipment->find( 'Specifications' => {'Inkjetting Capable'=>'When PerfectBound'}, 'useinestimating'=>1,'order'=>'lower(strName)') if $$services{'PerfectBound'};
	@{$$variable{'Equipment'}} = @possible_equipment;
} # end sub display

1;
__END__
