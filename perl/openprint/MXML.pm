use strict;
package openprint::MXML;

require Math::Calc::Units;
require XML::DOM;
require openprint::Paper;
require openprint::Imposition;
require openprint::Estimating::Printing;

my %runstyles = (
    'Sheet Work', 'Sheetwise',
    'Work & Turn', 'WorkAndTurn',
    'Perfecting','Perfected',
    'Work & Tumble','WorkAndTumble',
);

my $units = 'in';

sub new {

	my ( $parent, $P ) = @_;

    my $self = {};
    bless $self, $parent;

	my $doc = new XML::DOM::Document;
	$$self{'doc'} = $doc;
    $doc->setXMLDecl( $doc->createXMLDecl( '1.0' ) );
    my $MetrixXML = $doc->appendChild($doc->createElement('MetrixXML'));
    $MetrixXML->setAttribute('xmlns','http://www.lithotechnics.com');
    $MetrixXML->setAttribute('Status','Waiting');
    $MetrixXML->setAttribute('SchemaVersion','1.0');
    $MetrixXML->setAttribute('DocumentVersion','1.2');
    $MetrixXML->setAttribute('Units', $units eq 'in' ? 'Inches' : 'Millimeters' );
    #$MetrixXML->setAttribute('Units', 'Inches' );

	my $ResourcePool = $MetrixXML->appendChild( $doc->createElement('ResourcePool') );
	my $Project = $MetrixXML->appendChild( $doc->createElement('Project') );
	$Project->setAttribute( 'ProjectID', $P->docket() );
	$Project->setAttribute( 'Name', $P->reference() );
	$Project->setAttribute( 'Notes', $P->comments() );
	$Project->setAttribute( 'Description', $P->summary() );
	$Project->setAttribute( 'ReadOnly', 'False' );
	$Project->setAttribute( 'AutoNumberOut', 'True' );

	my $binding = $P->get_book_type();

	my $ProductPool = $Project->appendChild( $doc->createElement('ProductPool'));
	my $Product = $ProductPool->appendChild( $doc->createElement('Product') );
	my %services = $P->get_services();
	my $printing_specs = openprint::service::get_specs_ref( $P->id(), $services{''}[0] );
	$Product->setAttribute('ID', $P->id() );
	if ( $binding ) {
	$Product->setAttribute('Type', 'Bound');
	} elsif ( $services{'Folding'} ) {
	$Product->setAttribute('Type', 'Folded');
	} else {
	$Product->setAttribute('Type', 'Flat');
	} # end if
	$Product->setAttribute('FinishedTrimWidth',Math::Calc::Units::convert($$printing_specs{'txtFinalWidth'}.'in',$units));
	$Product->setAttribute('FinishedTrimHeight',Math::Calc::Units::convert($$printing_specs{'txtFinalHeight'}.'in',$units));
	$Product->setAttribute('RequiredQuantity',$P->ordered_quantity());

	my $RGBColor = $ResourcePool->appendChild( $doc->createElement('RGBColor') );
	$RGBColor->setAttribute('ID','Red');
	$RGBColor->setAttribute('Red','255');
	$RGBColor->setAttribute('Green','0');
	$RGBColor->setAttribute('Blue','0');

	my $DisplayColor = $Product->appendChild( $doc->createElement( 'DisplayColor'));
	my $RGBColorRef = $DisplayColor->appendChild( $doc->createElement( 'RGBColorRef' ) );
	$RGBColorRef->setAttribute('rRef','Red');
	my $ComponentPool = $Product->appendChild( $doc->createElement( 'ComponentPool' ) );
	my $LayoutPool = $Project->appendChild( $doc->createElement( 'LayoutPool' ) );
	my $page = 1;
	my $PagePool = $Product->appendChild( $doc->createElement( 'PagePool' ) );

	my $PageDefaults = $PagePool->appendChild( $doc->createElement( 'PageDefaults' ) );

	my $child_id = 0;
	my $parent_sig_id = 0;

	my ( $cover_sig_id ) = $P->signatures({'type'=>'Cover Pages'});
	my @signatures = $P->signatures();
	$cover_sig_id = shift @signatures if ! $cover_sig_id;
	@signatures = sets::exclude([$cover_sig_id], \@signatures );
	@signatures = ( $cover_sig_id, @signatures );

	for ( my $i = 0; $i < @signatures; $i += 1 ) {
		my $sig_id = $signatures[$i];
		my $sig_specs = openprint::service::get_specs_ref( $P, $sig_id );
		my @equipment = openprint::Equipment->find('strid'=>$$sig_specs{'ddmPress'.$P->ordered_quantity_index()});
		my $Equipment;
		if ( @equipment ) {
			$Equipment = shift @equipment;
		} else {
			$Equipment = new openprint::Equipment();
		} # end if

		my $PressNode = openprint::JDF::getNode( $ResourcePool, 'Press', 'ID'=>'E'.$Equipment->id() );
		if ( ! $PressNode ) {
			$PressNode = $ResourcePool->appendChild( $doc->createElement( 'Press' ) );
			$PressNode->setAttribute('ID','E'.$Equipment->id());
			$PressNode->setAttribute('DeviceID',$Equipment->strid());
		} # end if

		my $Component = $ComponentPool->appendChild( $doc->createElement( 'Component' ) );
		$Component->setAttribute('ID', 'Component'.$sig_id );
		$Component->setAttribute('RequestedNumberOut', $$sig_specs{'txtImposition'.$P->ordered_quantity_index()} );
		$Component->setAttribute('Priority', 5 );
		$Component->setAttribute('Active', 'True' );
		$Component->setAttribute('Cover', $$sig_specs{'txtSignatureType'} eq 'Cover Pages' ? 'True' : 'False' );
		$Component->setAttribute('CombinePages','False');

		if ( $sig_id != $cover_sig_id ) {
			my $ParentComponent = $Component->appendChild( $doc->createElement( 'ParentComponent' ));
			my $ComponentRef = $ParentComponent->appendChild( $doc->createElement('ComponentRef'));
			$ComponentRef->setAttribute('rRef','Component'.$signatures[$i-1] );
		} # end if
		if ( $P->signatures()==1 ) {
			$Component->setAttribute('OffcutTop', 0 );
			$Component->setAttribute('OffcutLeft', 0 );
			$Component->setAttribute('OffcutBottom', 0 );
			$Component->setAttribute('OffcutRight', 0 );
		} # end if
		if ( $$sig_specs{'chkOverrideGrainDirection'.$P->ordered_quantity_index()} eq 'Y' ) {
			$Component->setAttribute('FinishedGrain', $$sig_specs{'rdbGrainDirection'.$P->ordered_quantity_index()} );
		} else {
			$Component->setAttribute('FinishedGrain', 'Either' );
		} # end if
		if ( $sig_id == $cover_sig_id and $$sig_specs{'txtSignatureType'} ne 'Cover Pages' ) {
			$Component->setAttribute('ChildIndex', '-1' );
		} else {
			if ( $binding eq 'SaddleStitching' ) {
			$Component->setAttribute('ChildIndex', 0 );
			} else {
			$Component->setAttribute('ChildIndex', $child_id );
			$child_id += 1;
			} # end if
		} # end if

		my $Paper = openprint::Paper::load_from_signature( $P, $sig_specs );


		my $StockNode = openprint::JDF::getNode( $doc, 'Stock', 'ID'=>'Stock'.$Paper->id() );
		if ( ! $StockNode ) {
			$StockNode = $ResourcePool->appendChild( $doc->createElement('Stock') );
			$StockNode->setAttribute('ID','Stock'.$Paper->id());
			$StockNode->setAttribute('Vendor',$Paper->manufacturer());
			$StockNode->setAttribute('Name',$Paper->name());
			$StockNode->setAttribute('Weight',int($Paper->gsm()));
			$StockNode->setAttribute('WeightUnit','gsm');
			$StockNode->setAttribute('Thickness',Math::Calc::Units::convert( $Paper->calliper().'in', $units) );
			$StockNode->setAttribute('Grade',1);
		} # end if

		my $StockRef = $Component->appendChild( $doc->createElement('StockRef') );
		$StockRef->setAttribute('rRef', $StockNode->getAttribute('ID') );

		my $StockSheetNode = openprint::JDF::getNode( $StockNode, 'StockSheet', 'ID'=>'StockSheet'.$Paper->id() );
		if ( ! $StockSheetNode ) {
			$StockSheetNode = $StockNode->appendChild( $doc->createElement( 'StockSheet' ) );
			$StockSheetNode->setAttribute('ID', 'StockSheet'.$Paper->id() );
			if ( $Paper->width() > $Paper->height() ) {
			$StockSheetNode->setAttribute('Width',Math::Calc::Units::convert($Paper->width().'in',$units) );
			$StockSheetNode->setAttribute('Height',Math::Calc::Units::convert($Paper->height().'in',$units) );
			$StockSheetNode->setAttribute('Grain', 'Vertical' );
			} else {
			$StockSheetNode->setAttribute('Width',Math::Calc::Units::convert($Paper->height().'in',$units) );
			$StockSheetNode->setAttribute('Height',Math::Calc::Units::convert($Paper->width().'in',$units) );
			$StockSheetNode->setAttribute('Grain', 'Horizontal' );
			} # end if
		} # end if

		my $FoldingScheme = $ResourcePool->appendChild( $doc->createElement('FoldingScheme') );
		$FoldingScheme->setAttribute('ID','Fold-'.$sig_id);
		if ( $$sig_specs{'rdbTemplateType'} ) {
			$FoldingScheme->setAttribute('JDFFoldCatalog',$openprint::JDF::folds{$$sig_specs{'rdbTemplateType'}} );
		} else {
			$FoldingScheme->setAttribute('JDFFoldCatalog',$openprint::JDF::folds{$$sig_specs{'PageQuantity'.$P->ordered_quantity_index()}.'PageFold'} );
		} # end if

		my $FoldingSchemeRef = $Component->appendChild( $doc->createElement('FoldingSchemeRef'));
		$FoldingSchemeRef->setAttribute('rRef', 'Fold-'.$sig_id);
	
		# Now add Layouts
		my $Layout = $LayoutPool->appendChild( $doc->createElement( 'Layout' ) );
		my %Colors;
		foreach my $side ( 'SideOne','SideTwo' ) {
			@{$Colors{$side}} = openprint::Estimating::Printing::get_colours( $sig_specs, $side );
		} # end foreach side
		
		if ( @{$Colors{'SideOne'}} and @{$Colors{'SideTwo'}} ) {
		$Layout->setAttribute('PrintingMethod', $runstyles{$$sig_specs{'ddmRunStyle'.$P->ordered_quantity_index()}} );
		} else {
		$Layout->setAttribute('PrintingMethod', 'OneSided' );
		} # end if
		$Layout->setAttribute('PageToBleedGap', Math::Calc::Units::convert($$sig_specs{'ddmBleedSize'.$P->ordered_quantity_index()}.'in',$units ) );
		$$sig_specs{'txtPressSheetQty'.$P->ordered_quantity_index()} =~ s/(\d*).*/$1/g;
		$Layout->setAttribute('SheetsRequired', $$sig_specs{'txtPressSheetQty'.$P->ordered_quantity_index()} );
		if ( sets::isin( $$sig_specs{'ddmRunStyle'.$P->ordered_quantity_index()}, ['Work & Turn','Work & Tumble','Perfecting'] ) ) {
				my $SheetSide = $Layout->appendChild( $doc->createElement( 'SheetSide' ) );
				$SheetSide->setAttribute('Side',1);
				my $PressRef = $SheetSide->appendChild( $doc->createElement( 'PressRef' ) );
				$PressRef->setAttribute('rRef', 'E'.$Equipment->id() );
		} else {
			if ( @{$Colors{'SideOne'}} ) {
				my $SheetSide = $Layout->appendChild( $doc->createElement( 'SheetSide' ) );
				$SheetSide->setAttribute('Side',1);
				my $PressRef = $SheetSide->appendChild( $doc->createElement( 'PressRef' ) );
				$PressRef->setAttribute('rRef', 'E'.$Equipment->id() );
			} # end if
			if ( @{$Colors{'SideTwo'}} ) {
				my $SheetSide = $Layout->appendChild( $doc->createElement( 'SheetSide' ) );
				$SheetSide->setAttribute('Side',2);
				my $PressRef = $SheetSide->appendChild( $doc->createElement( 'PressRef' ) );
				$PressRef->setAttribute('rRef', 'E'.$Equipment->id() );
			} # end if
		} # end if
		my $StockSheetRef = $Layout->appendChild( $doc->createElement( 'StockSheetRef' ) );
		$StockSheetRef->setAttribute('rRef','StockSheet'.$Paper->id());

		my $ComponentRefPool = $Layout->appendChild( $doc->createElement( 'ComponentRefPool' ) );
		my $ComponentRef = $ComponentRefPool->appendChild( $doc->createElement( 'ComponentRef' ) );
		$ComponentRef->setAttribute('rRef','Component'.$sig_id);

		foreach my $spread ( 1 .. $$sig_specs{'PageQuantity'.$P->ordered_quantity_index()} ) {
			foreach my $side ( 'SideOne','SideTwo' ) {
				next if ! @{$Colors{$side}};
				$PagePool->appendChild( addPage( $doc, $P, $sig_specs, $page, $side, \%Colors, $ResourcePool ) );
				$page += 1;
			} # end foreach
		} # end foreach
		$parent_sig_id = $sig_id;
	} # end foreach signature


	if ( $P->signatures() > 1 ) {
		my $Binder;

		if ( $services{$binding} ) {
			my $binding_specs = openprint::service::get_specs_ref( $P->id(), $services{$binding}[0] );
			my @equipment = openprint::Equipment->find('strid'=>$$binding_specs{'ddmEquipment'.$P->ordered_quantity_index()});
			$Binder = shift @equipment;
		} # end if
		if ( $Binder ) {
			my $BindingMachine = $ResourcePool->appendChild( $doc->createElement( 'BindingMachine' ) );
			$BindingMachine->setAttribute('ID','E'.$Binder->id());
			$BindingMachine->setAttribute('DeviceID',$Binder->strid());
			my $BindingMachineRef = $Product->appendChild( $doc->createElement('BindingMachineRef') );
			$BindingMachineRef->setAttribute('rRef',$BindingMachine->getAttribute('ID'));
		} # end if
	} # end if

	my $Customer = $ResourcePool->appendChild( $doc->createElement( 'Customer' ) );
	my $C = $P->Company();
	$Customer->setAttribute('CompanyName',$C->name() );
	$Customer->setAttribute('CompanyID',$C->id() );
	$Customer->setAttribute('WebAddress',$C->url() );
	$Customer->setAttribute('City',$C->city() );
	$Customer->setAttribute('CountryCode',$C->country() );
	$Customer->setAttribute('PostalCode',$C->postalcode() );
	$Customer->setAttribute('Region',$C->state() );
	$Customer->setAttribute('Street',$C->address1() . $C->address2() );
	
	my $AuditPool = $MetrixXML->appendChild( $doc->createElement( 'AuditPool' ) );
	my $Audit = $AuditPool->appendChild( $doc->createElement('Audit'));
	$Audit->setAttribute('Event','Created');
	$Audit->setAttribute('AgentName','IntelligentQuote');
	$Audit->setAttribute('AgentVersion','2.0');
	my @gmtime = gmtime(time);
	$Audit->setAttribute('TimeStamp', sprintf('%.4d-%.2d-%.2dT%.2d:%.2d:%.2dZ', $gmtime[5]+1900, $gmtime[4]+1, $gmtime[3]+1,$gmtime[2],$gmtime[1],$gmtime[0] ) );
	
	return $self;
} # end sub new

sub toString {
	my $self = shift;
	return $$self{'doc'}->toString();
} # end sub toString

sub addPage {
	my ( $doc, $P, $sig_specs, $page, $side, $Colors, $ResourcePool ) = @_;

	my $Page = $doc->createElement('Page');
	$Page->setAttribute('Number',$page);
	$Page->setAttribute('Folio',$page);
	foreach my $bleed ( 'Left','Right','Top','Bottom' ) {
		$Page->setAttribute('Bleed'.$bleed, $$sig_specs{'Bleed'.$bleed} ? Math::Calc::Units::convert($$sig_specs{'ddmBleedSize'.$P->ordered_quantity_index()}.'in',$units) : 0 );
	} # end foreach bleed
	foreach my $colour ( @{$$Colors{$side}} ) {
		my $InkNode = openprint::JDF::getNode( $doc, 'Ink', 'ID'=>'Ink'.$colour );
		if ( ! $InkNode ) {
			$InkNode = $ResourcePool->appendChild( $doc->createElement( 'Ink' ) );
			$InkNode->setAttribute( 'ID', 'Ink'.$colour );
			$InkNode->setAttribute('Name',$colour);
			if ( sets::isin( $colour, ['Cyan','Magenta','Yellow','Black'] ) ) {
				$InkNode->setAttribute('Type','Process'.$colour);
				my $CMYKColor = $ResourcePool->appendChild( $doc->createElement('CMYKColor') );
				$CMYKColor->setAttribute('ID',$colour);
				$CMYKColor->setAttribute('Cyan', $colour eq 'Cyan' ? '100' : 0 );
				$CMYKColor->setAttribute('Magenta', $colour eq 'Magenta' ? '100' : 0 );
				$CMYKColor->setAttribute('Yellow', $colour eq 'Yellow' ? '100' : 0 );
				$CMYKColor->setAttribute('Black', $colour eq 'Black' ? '100' : 0 );
				my $CMYKColorRef = $InkNode->appendChild( $doc->createElement('CMYKColorRef') );
				$CMYKColorRef->setAttribute('rRef',$colour);
			} elsif ( $colour =~ /Varnish/ ) {
				$InkNode->setAttribute('Type','Varnish');
				my $CMYKColor = $ResourcePool->appendChild( $doc->createElement('CMYKColor') );
				$CMYKColor->setAttribute('ID',$colour);
				$CMYKColor->setAttribute('Cyan', 0 );
				$CMYKColor->setAttribute('Magenta', 0 );
				$CMYKColor->setAttribute('Yellow', 20 );
				$CMYKColor->setAttribute('Black', 0 );
				my $CMYKColorRef = $InkNode->appendChild( $doc->createElement('CMYKColorRef') );
				$CMYKColorRef->setAttribute('rRef',$colour);
			} else {
				$InkNode->setAttribute('Type','SpotColor');
				my $CMYKColor = $ResourcePool->appendChild( $doc->createElement('CMYKColor') );
				$CMYKColor->setAttribute('ID',$colour);
				$CMYKColor->setAttribute('Cyan', 0 );
				$CMYKColor->setAttribute('Magenta', 0 );
				$CMYKColor->setAttribute('Yellow', 20 );
				$CMYKColor->setAttribute('Black', 0 );
				my $CMYKColorRef = $InkNode->appendChild( $doc->createElement('CMYKColorRef') );
				$CMYKColorRef->setAttribute('rRef',$colour);
			} # end if
		} # end if
		my $InkRef = $Page->appendChild( $doc->createElement('InkRef'));
		$InkRef->setAttribute('rRef', $InkNode->getAttribute('ID'));
	} # end foreach
	return $Page;
} # end sub addPage

	1;
	__END__
