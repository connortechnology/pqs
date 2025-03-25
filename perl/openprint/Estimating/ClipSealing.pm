package openprint::Estimating::ClipSealing;
use vars qw( %ServicePrices );
use strict;
%ServicePrices = (
	ClipSealingMakeReady		=> { },
	ClipSealingMinimumCharge	=> { },
	ClipSealing	=> { units => [ 'per m' ] },
	ClipSealing1Clips	=> { },
	ClipSealing2Clips	=> { },
	ClipSealing3Clips	=> { },
);

require POSIX;
require openprint::service;
require openprint::Project;

my @variables = (
	'alert',
	'SealQuantity','SealType_id',
	'ddmEquipment1', 'ddmEquipment2', 'ddmEquipment3',
	'txtQuantity1', 'txtQuantity2', 'txtQuantity3',
	'Markup1', 'Markup2', 'Markup3',
	'txtPrice1', 'txtPrice2', 'txtPrice3',
	'MPrice1', 'MPrice2', 'MPrice3',
	'OverridePrice1', 'OverridePrice2', 'OverridePrice3',
);

sub variables {
	return @variables;
} # end sub variables

sub calc {
  my ($log, $dbh, $variable, $pid, $sid, $specs) = @_;

	my $Project = new openprint::Project( $pid );
	my $services = $Project->services();
	my @signatures = $Project->signatures();
	my $sig_specs = openprint::service::get_specs_ref( $Project, $signatures[0] );
	my $form = $$sig_specs{SignatureIndex};
	my $folding_specs;

	my @capable = ('Y');
	if ( $$services{SaddleStitching} ) {
		push @capable, 'When Stitching';
	} elsif ( $$services{Folding} ) {
		push @capable, 'When Folding';
		$folding_specs = openprint::service::get_specs_ref( $Project, $$services{Folding}[0] );
	} # end if

  $$specs{alert} = '';
	if (!$$specs{SealQuantity}) {
		$$specs{alert} = 'Please enter the # of clips.<br/>';
		return $$specs{Status} = 'uncalculated';
	} # end if

	my $status = 'calculated';
	my @equipment = openprint::Equipment->find( Specifications=>{ 'ClipSealing Capable'=>\@capable },useinestimating=>1);
	if ( ! @equipment ) {
		$$specs{alert} = 'We have no clip sealing equipment.<br/>';
		return $$specs{Status} = 'uncalculated';
	} # end if

	if ( ! $$specs{SealType_id} ) {
		my @Materials = openprint::Material->find(category=>'Clip Seal Types');
		if ( @Materials == 1 ) {
			$$specs{SealType_id};
		} elsif ( @Materials > 1 ) {
			$$specs{alert} .= 'Please select the type of clip seal.<br/>';
			return $$specs{Status} = 'uncalculated';
		} # end if
	} # end if
	my $Material = new openprint::Material( $$specs{SealType_id} );

  foreach my $qty_index ( $Project->quantity_indexes() ) {
    $$specs{'txtPrice'.$qty_index} =~ s/[^\d\.]//g;
    $$specs{'Markup'.$qty_index} =~ s/[^\-\d\.]//g;
    $$specs{'txtQuantity'.$qty_index} = $Project->quantity() if ! $$specs{'txtQuantity'.$qty_index};
    $$specs{'hdnBreakdown'.$qty_index} = '';

    my %BestPrice;

    foreach my $Equipment ( @equipment ) {
      $$specs{'hdnBreakdown'.$qty_index} .= '<fieldset><legend>'.$Equipment->name().'</legend>';
      my $clips_per_run = $Equipment->specification('Clips Per Run');
      if ( ! int($clips_per_run) ) {
        $$specs{'hdnBreakdown'.$qty_index} .= 'No Clips Per Run setting.<br/></fieldset>';
        next;
      } # end if
      if ( $Equipment->specification('ClipSealing Capable') eq 'When Folding' ) {
        if ( $Equipment->id() != $$folding_specs{"ddmEquipment-$form-$qty_index"} ) {
          $$specs{'hdnBreakdown'.$qty_index} .= 'Not folding on ' . $Equipment->name() . '. Folding on '.new openprint::Equipment($$folding_specs{"ddmEquipment-$form-$qty_index"})->name().'<br/></fieldset>';
          next;
        } # end if
      } # end if
      if ( $_ = $Equipment->specification('ClipSealing Maximum Quantity') and $_ < $$specs{'txtQuantity'.$qty_index} ) {
        $$specs{'hdnBreakdown'.$qty_index} .= "Has Maximum Quantity and $_ < " . $$specs{'txtQuantity'.$qty_index}.'<br/></fieldset>';
        next;
      } elsif ( $_ = $Equipment->specification('ClipSealing Minimum Quantity') and $_ > $$specs{'txtQuantity'.$qty_index} ) {
        $$specs{'hdnBreakdown'.$qty_index} .= "Has Minimum Quantity and $_ > " . $$specs{'txtQuantity'.$qty_index}.'<br/></fieldset>';

        next;
      } # end if

      my $runs = POSIX::ceil( $$specs{SealQuantity} / $clips_per_run );

      my $totalPrice = 0;
      my %MakeReadyPrice = openprint::service::get_price_object( 'ClipSealingMakeReady', $$specs{SealQuantity}, $Equipment );
      if ( %MakeReadyPrice ) {
        $$specs{'hdnBreakdown'.$qty_index} .= sprintf('MakeReady Price: $%1$.2f%2$s<br/>', @MakeReadyPrice{'Price','units'} );
        $totalPrice += $MakeReadyPrice{Price};
      } else {
        $$specs{'hdnBreakdown'.$qty_index} .= 'No MakeReady Price.<br/>';
      } # end if

      my %ServicePrice = openprint::service::get_price_object('ClipSealing'.$$specs{SealQuantity}.'Clips', $$specs{'txtQuantity'.$qty_index}, $Equipment );
      %ServicePrice = openprint::service::get_price_object('ClipSealing', $$specs{'txtQuantity'.$qty_index}, $Equipment ) if ! %ServicePrice;
      if ( ! %ServicePrice ) {
        $$specs{'hdnBreakdown'.$qty_index} .= 'No Service Price.<br/>';
      } elsif ( $ServicePrice{units} eq 'per m' ) {
        $ServicePrice{Total} = $ServicePrice{Price} * $$specs{'txtQuantity'.$qty_index} * $runs/ 1000;
        $$specs{'hdnBreakdown'.$qty_index} .= sprintf('Service Price: $%1$s%2$s * %4$d seals * %5$d = $%3$.2f<br/>', @ServicePrice{'Price','units','Total'}, @$specs{'SealQuantity','txtQuantity'.$qty_index} );
        $totalPrice += $ServicePrice{Total};
      } else {
        $$specs{'hdnBreakdown'.$qty_index} .= 'Unknown units for Service Price<br/>';
      } # end if


      my %MaterialPrice;
      if ( $$specs{SealType_id} ) {
        %MaterialPrice = $Material->get_price( $$specs{'txtQuantity'.$qty_index} * $$specs{SealQuantity} );
        if ( ! %MaterialPrice ) {
          $$specs{'hdnBreakdown'.$qty_index} .= 'No Material Price.<br/>';
        } elsif ( $MaterialPrice{units} eq 'per m' ) {
          $MaterialPrice{Total} = $MaterialPrice{Price} * $$specs{'txtQuantity'.$qty_index} * $$specs{SealQuantity} /1000;
          $$specs{'hdnBreakdown'.$qty_index} .= sprintf('Material Price: $%1$s%2$s * %4$d seals * %5$d = $%3$.2f<br/>', @MaterialPrice{'Price','units','Total'}, @$specs{'SealQuantity','txtQuantity'.$qty_index} );
          $totalPrice += $MaterialPrice{Total};
        } elsif ( $MaterialPrice{units} eq 'per seal' ) {
          $MaterialPrice{Total} = $MaterialPrice{Price} * $$specs{'txtQuantity'.$qty_index} * $$specs{SealQuantity};
          $$specs{'hdnBreakdown'.$qty_index} .= sprintf('Material Price: $%1$s%2$s * %4$d seals * %5$d = $%3$.2f<br/>', @MaterialPrice{'Price','units','Total'}, @$specs{'SealQuantity','txtQuantity'.$qty_index} );
          $totalPrice += $MaterialPrice{Total};
        } else {
          $$specs{'hdnBreakdown'.$qty_index} .= 'Unknown units for Material Price<br/>';
        } # end if
      } # end if

      $$specs{'hdnBreakdown'.$qty_index} .= sprintf('Total: $%.2f', $totalPrice );
      if ( my $min_price = openprint::service::get_price('ClipSealingMinimumCharge', undef, $Equipment ) ) {
        $totalPrice = $min_price if $totalPrice < $min_price;
      } # end if

      if ( (!defined $BestPrice{Total}) or $totalPrice < $BestPrice{Total} ) {
        $BestPrice{Total} = $totalPrice;
        $BestPrice{Equipment} = $Equipment;
        $BestPrice{ServicePrice} = \%ServicePrice;
        $BestPrice{MaterialPrice} = \%MaterialPrice
      } # end if
      $$specs{'hdnBreakdown'.$qty_index} .= '</fieldset>';
    } # end foreach Equipment

    if ( ! defined $BestPrice{Total} ) {
      $$specs{alert} .= 'Unable to calculate a price for quantity ' . $qty_index . '.<br/>';
      $status = 'uncalculated';
    } else {
      $$specs{'ddmEquipment'.$qty_index} = $BestPrice{Equipment}->id();
    } # end if

    $$specs{"txtUnitPrice$qty_index"} = sprintf($openprint::config{UnitPriceFormat},
      ( ( $BestPrice{ServicePrice}{Total} + $BestPrice{MaterialPrice}{Total} ) / $$specs{'txtQuantity'.$qty_index} ) * (1+$Project->markup()/100)
    );
    $$specs{"MPrice$qty_index"} = sprintf($openprint::config{UnitPriceFormat}, (($BestPrice{ServicePrice}{Total} + $BestPrice{MaterialPrice}{Total} ) / $$specs{'txtQuantity'.$qty_index} ) * 1000 );
    if ( $$specs{'OverridePrice'.$qty_index} ne 'Y' ) {
      $$specs{'txtPrice'.$qty_index} = sprintf( $openprint::config{ProjectMoneyFormat}, 
        $BestPrice{Total} * (1+$$specs{'Markup'.$qty_index}/100) * (1+$Project->markup()/100) );
    } else {
      $$specs{'txtPrice'.$qty_index} = sprintf( $openprint::config{ProjectMoneyFormat}, $$specs{'txtPrice'.$qty_index} );
    } # end if
  } # end foreach qty_index

  return $$specs{Status} = $status;
} # end sub calc

sub summary {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;

	if ( $qty_index ) {
		return '';
	} # end if
	$specs = openprint::service::get_specs_ref( $Project, $service_id ) if ( ! $specs );

	return $$specs{SealQuantity} . ' ' . ( $$specs{SealType_id} ? new openprint::Material( $$specs{SealType_id} )->description() : ' Clip Seal');
} # end sub summary

sub display {
	my ( $log, $dbh, $variable, $project_index, $service_index ) = @_;

	my $Project = new openprint::Project( $project_index );
	my $services = $Project->services();
	$$variable{Equipment} = [ openprint::Equipment->find( Specifications => {'ClipSealing Capable'=>['Y',
			( $$services{Folding} ? 'When Folding' : () )
			]}, useinestimating=>1,'order'=>'lower(strName)') ];
} # end sub display

sub save {
} # end sub save
1;
__END__
