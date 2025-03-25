package openprint::Estimating::SoftFolding;
use strict;

require openprint::service;
use POSIX           qw(ceil);

use constant DEBUG => 0;

my %variables = (
	'Folds' => ['save'],
	'ddmEquipment1' => ['save','output'], 'ddmEquipment2' => ['save','output'], 'ddmEquipment3' => ['save','output'],
	'OverridePrice1' => ['save'], 'OverridePrice2' => ['save'], 'OverridePrice3' => ['save'],
	'txtPrice1' => ['save','output'], 'txtPrice2' => ['save','output'], 'txtPrice3' => ['save','output'],
	'txtQuantity1' => ['save'], 'txtQuantity2' => ['save'], 'txtQuantity3' => ['save'],
	'Markup1'=>['save'], 'Markup2'=>['save'], 'Markup3'=>['save'],
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


sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $specs) = @_;

	my $Project = new openprint::Project( $pid );

	if ( $Project->Type()->name() ne 'MultiPage' ) {
		$$specs{'alert'} = 'Soft Folding is only relevant for multi-page publications.';
		return $$specs{'Status'} = 'uncalculated';
	} # end if

	$$specs{'Folds'} =~ s/\D//g;
	#if ( ! $$specs{'Folds'} ) {
		#$$specs{'alert'} = 'Please enter the # of folds.';
		#return $$specs{'Status'} = 'uncalculated';
	#} # end if

	my @Equipment = openprint::Equipment->find('Specifications'=>{'SoftFolding Capable'=>'Y'},'useinestimating'=>1);
	if ( ! @Equipment ) {
		$$specs{'alert'} = 'We have no soft folding equipment.';
		return $$specs{'Status'} = 'uncalculated';
	} # end if

	my $services = $Project->services();
	my $project_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] ) if $$services{''};
	my $finished_calliper = $Project->calliper();

	my $status = 'calculated';

	foreach my $qty_index ( $Project->quantity_indexes() ) {
		$$specs{'Markup'.$qty_index} =~ s/[^\d\.\-]//g;
		$$specs{'txtPrice'.$qty_index} =~ s/[^\d\.]//g;
		$$specs{'txtQuantity'.$qty_index} =~ s/[^\d\.]//g;
		$$specs{'txtQuantity'.$qty_index} = $Project->quantity( $qty_index ) if ! $$specs{'txtQuantity'.$qty_index};
		next if ! $$specs{'txtQuantity'.$qty_index};

		my %BestPrice;
		$$specs{'hdnBreakdown'.$qty_index} = sprintf( '%d pages, %.3f"<br/>', $$project_specs{'txtTotalPageQuantity'}, $finished_calliper );

		foreach my $Equipment ( @Equipment ) {
			$$specs{'hdnBreakdown'.$qty_index} .= '<fieldset><legend>'.$Equipment->name().'</legend>';

			if ( $_ = $Equipment->fits( @$project_specs{'txtFinalWidth','txtFinalHeight'}, $finished_calliper, 'SoftFolding' ) ) {
				$$specs{'hdnBreakdown'.$qty_index} .= $_;
				if ( @Equipment == 1 ) {
					$$specs{'alert'} .= $_;
				} # end if
				next;
			} # end if

			my $total = 0;

			my %MakeReady = openprint::service::get_price_object('SoftFoldingMakeReady', undef, $Equipment );
			if ( ! %MakeReady ) {
				$$specs{'hdnBreakdown'.$qty_index} .= 'No MakeReady price.<br/>';
			} else {
				$$specs{'hdnBreakdown'.$qty_index} .= sprintf('MakeReady Price: $%1$.2f%2$s<br/>', @MakeReady{'Price','units'} );
				$total += $MakeReady{'Price'};
			} # end if

			my %ServicePrice = openprint::service::get_price_object( 'SoftFolding'.$$project_specs{'txtTotalPageQuantity'}.'Page', $finished_calliper, $Equipment ); 
			if ( ! %ServicePrice ) {
				%ServicePrice = openprint::service::get_price_object('SoftFolding', undef, $Equipment); 
			} # end if
			if ( %ServicePrice ) {
				if ( $ServicePrice{range_units} eq 'calliper' ) {
					%ServicePrice = openprint::service::get_price_object('SoftFolding', $finished_calliper, $Equipment); 
				} else {
					%ServicePrice = openprint::service::get_price_object('SoftFolding', $$specs{'txtQuantity'.$qty_index}, $Equipment); 
				}
			}
			if ( ! %ServicePrice ) {
				$$specs{'hdnBreakdown'.$qty_index} .= 'No Service price.<br/>';
			} elsif ( lc $ServicePrice{'units'} eq 'per m' ) {
				$ServicePrice{'Total'} += $$specs{Folds} * $ServicePrice{'Price'} * $$specs{'txtQuantity'.$qty_index} / 1000;
			} else {
				$ServicePrice{'Total'} += $$specs{Folds} * $ServicePrice{'Price'} * $$specs{'txtQuantity'.$qty_index};
			} # end if
			$total += $ServicePrice{'Total'};
			$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Service Price: $%1$.2f%2$s = $%3$.2f<br/>', @ServicePrice{'Price','units','Total'} );

			if ( my $minimumcharge = openprint::service::get_price('SoftFoldingMinimumCharge', undef, $Equipment ) ) {
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
				( ($BestPrice{'ServicePrice'}{'Total'} + $BestPrice{'LastServicePrice'}{'Total'} ) / $$specs{'txtQuantity'.$qty_index} ) * (1+$Project->markup()/100) );
		if ( $$specs{'OverridePrice'.$qty_index} ne 'Y' ) {
			$$specs{'txtPrice'.$qty_index} = sprintf( $openprint::config{'ProjectMoneyFormat'}, $BestPrice{'Total'}*(1+$$specs{"Markup$qty_index"}/100)*(1+$Project->markup()/100) );
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

	return $$specs{Folds} . ' soft folds';
} # end sub summary

sub display {
	my ( $log, $dbh, $variable, $project_index, $service_index ) = @_;

	@{$$variable{'Equipment'}} = openprint::Equipment->find( 
			'Specifications'	=>	{'SoftFolding Capable'=>'Y'},
			'useinestimating'	=>	1,
			'order'				=>	'lower(strName)'
			);
$openprint::log->warn("SoftFolding Equipment: " . @{$$variable{'Equipment'}} );
} # end sub display

1;
__END__
