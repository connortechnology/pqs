package openprint::JDF;

require JMF;
use openprint::Imposition;

use vars qw( %runstyles %folds %bindingtypes %coatings );
use strict;

#maps openprint to jdf runstyles
%runstyles = (
	'Sheet Work', 'WorkAndBack',
	'Work & Turn', 'WorkAndTurn',
	'Perfecting','Perfecting',
	'Work & Tumble','WorkAndTumble',
	'Work & Back','WorkAndBack',
	'Web','Simplex',
);

my %bindingtypes = (
'SaddleStitching'=>'SaddleStitch',
'LoopStitching'=>'SaddleStitch',
'PerfectBound'=>'SoftCover',
'SpinePaste'=>'EdgeGluing',
);

my %coatings = (
	'Gloss'		=>'Glossy',
	'Matte'		=>'Matte',
	'Satin'		=>'Sating',
	'Semigloss'	=>'Semigloss',
	'None'		=>'None',
	'Coated'	=>'Coated',
	'HighGloss'	=>'HighGloss',
);

%folds = (
	'NoFold'		=>	'F2-1',
	'2PanelFold'	=>	'F4-1',
	'3PanelFold'	=>	'F6-4',
	'3PanelZFold'	=>	'F6-1',
	'4PanelFold'	=>	'F8-4',
	'4PanelZFold'	=>	'F8-3',
	'4PageFold'		=>	'F4-1',
	'4PageSignatureFold'		=>	'F4-1',
	'8PageFold'		=>	'F8-7',
	'12PageFold'		=>	'F12-8',
	'16PageFold'		=>	'F16-6',
	'24PageFold'		=>	'F24-6',
	'28PageFold'		=>	'F28-6',
	'32PageFold'		=>	'F32-6',
);

sub ProductType {
	my ( $Project, $sig_specs ) = @_;
	if ( $$sig_specs{'txtSignatureType'} eq 'Cover Pages' ) {
		return 'Cover';
	} elsif ( $$sig_specs{'txtSignatureType'} eq 'Interior Pages' ) {
		return 'Body';
	} elsif ( sets::isin( $Project->Type->name(), [ 'Brochures','Flyers' ] ) ) {
		return 'Brochure';
	} elsif ( sets::isin( $Project->Type->strid(), [ 'Poster' ] ) ) {
		return 'Poster';
	} # end if
	return 'Body';
} # end sub ProductType

sub getNode {
	my ( $doc, $tagname, %filters ) = @_;
	my $nodes = $doc->getElementsByTagName ($tagname);
    if ( $nodes->getLength() ) {
		if ( ! %filters ) {
			return $nodes->item(0);
		} else {
			for ( my $i = 0; $i < $nodes->getLength(); $i += 1 ) {
				my $item = $nodes->item( $i );
				my $flag = 1;
				foreach my $key ( %filters ) {
					if ( $item->getAttribute($key) ne $filters{$key} ) {
						$flag = 0;
					} # end if
				} # end foreach filter key=4
				return $item if $flag;
			} # end for $i
		} # end if
	} else {
$openprint::log->warn("Node not found $tagname");
	} # end if
}

sub Prepress {
    my ( $doc, $Project, $sig_id, $sig_specs ) = @_;

$openprint::log->debug("Starting JDF Prepress");	

	my $Prepress = $doc->createElement('JDF');
    #$project->setAttribute('xmlns','http://www.cip4.org/JDFSchema_1_1');
    #$project->setAttribute('Version','1.2');
    # Printing Part # is project + sig, cuz a docket can have multiple projects, and we are talking about printing a sig
         # This is so that the JMF handler can reference back to the service
	#$project->setAttribute('JobPartID',$Project->id() . '#' . $sig_id );
    $Prepress->setAttribute('Status','Waiting');
    $Prepress->setAttribute('Type','ProcessGroup');
	$Prepress->setAttribute('Category', 'PrePress' );
	$Prepress->setAttribute('ID', 'PRE'.$sig_id );
    $Prepress->setAttribute('JobPartID','PRE'.$sig_id);
	my $summary = openprint::service::summary( $Project->id(), $sig_id );
	$summary =~ s/<br\/>/ /g;
	$Prepress->setAttribute('DescriptiveName', 'PrePress '.$summary );

	my $ResourcePool = $Prepress->appendChild( $doc->createElement('ResourcePool') );
	my $ResourceLinkPool = $Prepress->appendChild( $doc->createElement('ResourceLinkPool') );

	my $Assembly = $ResourcePool->appendChild( Assembly( $doc, $Project, $sig_id, $sig_specs ) );

	my $BinderySignature = $ResourcePool->appendChild( BinderySignature( $doc, $Project, $sig_id, $sig_specs ) );

	my @side_one_colours = openprint::Estimating::Printing::get_colours( $sig_specs, 'SideOne' );
	my @side_two_colours = openprint::Estimating::Printing::get_colours( $sig_specs, 'SideTwo' );
	my $RunListFile = $ResourcePool->appendChild( $doc->createElement('RunList') );
	$RunListFile->setAttribute('ID','RNL'.$$sig_specs{'SignatureIndex'}.'_File');
	$RunListFile->setAttribute('Class','Parameter');
	$RunListFile->setAttribute('Status','Available');
	if ( $$sig_specs{'PageQuantity'.$Project->ordered_quantity_index()} ) {
		$RunListFile->setAttribute('NPage',$$sig_specs{'PageQuantity'.$Project->ordered_quantity_index()} );
	} elsif ( @side_one_colours and @side_two_colours ) {
		$RunListFile->setAttribute('NPage',2);
	} else {
		$RunListFile->setAttribute('NPage',1);
	} # end if

	my $LayoutElement = $RunListFile->appendChild( $doc->createElement('LayoutElement') );
	my $FileSpec = $LayoutElement->appendChild( $doc->createElement('FileSpec'));
	$FileSpec->setAttribute('MimeType','application/pdf');
	$FileSpec->setAttribute('URL','Content/File.pdf');

	my $RunListDocument = $ResourcePool->appendChild( $doc->createElement('RunList') );
	$RunListDocument->setAttribute('ID','RNL'.$$sig_specs{'SignatureIndex'}.'_Document');
	$RunListDocument->setAttribute('Class','Parameter');
	$RunListDocument->setAttribute('Status','Unavailable');

	my $RunListMarks = $ResourcePool->appendChild( $doc->createElement('RunList') );
	$RunListMarks->setAttribute('ID','RNL'.$$sig_specs{'SignatureIndex'}.'_Marks');
	$RunListMarks->setAttribute('Class','Parameter');
	$RunListMarks->setAttribute('Status','Unavailable');

	my $StrippingParams = $ResourcePool->appendChild( StrippingParams( $doc, $Project, $sig_id, $sig_specs ) );
	#my $PrePressPreparation = $Prepress->appendChild( PrePressPreparation( $doc, $Project, $sig_id, $sig_specs ) );
	#my $ImpositionPreparation = $Prepress->appendChild( ImpositionPreparation( $doc, $Project, $sig_id, $sig_specs ) );
$openprint::log->debug("Leaveing JDF Prepress");	
	return $Prepress;

} # end sub JDF_Prepress

sub PrePressPreparation {
    my ( $doc, $Project, $sig_id, $sig_specs ) = @_;
$openprint::log->debug("Starting JDF PrePressPreparation");	
	my $PPP = $doc->createElement('JDF');
    $PPP->setAttribute('Status','Waiting');
    $PPP->setAttribute('Category','PrePressPreparation');
    $PPP->setAttribute('DescriptiveName','PrePressPreparation of ' . $$sig_specs{'txtSignatureType'} . $$sig_specs{'SignatureIndex'} );
    $PPP->setAttribute('Type','ProcessGroup');
    $PPP->setAttribute('Types','PrePressPreparation');
	$PPP->setAttribute('ID', 'PPP'.$sig_id );
	$PPP->setAttribute('JobPartID', 'PPP'.$sig_id );
	my $RLP = $PPP->appendChild( $doc->createElement('ResourceLinkPool') );
	my $InputLink = $RLP->appendChild( $doc->createElement('RunListLink') );
	$InputLink->setAttribute('Usage','Input');
	$InputLink->setAttribute('ProcessUsage','Document');
	$InputLink->setAttribute('rRef','RNL'.$$sig_specs{'SignatureIndex'}.'_File');


	my $OutputLink = $RLP->appendChild( $doc->createElement('RunListLink') );
	$OutputLink->setAttribute('Usage','Output');
	$OutputLink->setAttribute('ProcessUsage','Document');
	$OutputLink->setAttribute('rRef','RNL'.$$sig_specs{'SignatureIndex'}.'_Document');
$openprint::log->debug("Leavting JDF PrePressPreparation");	
	return $PPP;
} # end sub PrePressPreparation

sub ImpositionPreparation {
    my ( $doc, $Project, $sig_id, $sig_specs ) = @_;
$openprint::log->debug("Starting JDF ImpositionPreparation");	
	my $IP = $doc->createElement('JDF');
    $IP->setAttribute('Status','Waiting');
    $IP->setAttribute('Category','ImpositionPreparation');
    $IP->setAttribute('DescriptiveName','ImpositionPreparation of ' . $$sig_specs{'txtSignatureType'} );
	$IP->setAttribute('ID', 'STR'.$sig_id );
	$IP->setAttribute('JobPartID', 'STR'.$sig_id );
    $IP->setAttribute('Type','ProcessGroup');
    $IP->setAttribute('Types','ImpositionPreparation');

	my $RLP = $IP->appendChild( $doc->createElement( 'ResourceLinkPool' ) );
	my $StrippingParamsLink = $RLP->appendChild( $doc->createElement( 'StrippingParamsLink' ) );
	$StrippingParamsLink->setAttribute('Usage','Input');
	$StrippingParamsLink->setAttribute('rRef','STP'.$sig_id);
	my $AssemblyLink = $RLP->appendChild( $doc->createElement( 'AssemblyLink' ) );
	$AssemblyLink->setAttribute('Usage','Input');
	$AssemblyLink->setAttribute('rRef','ASM100'.$sig_id);
	my $LayoutLink = $RLP->appendChild( $doc->createElement( 'LayoutLink' ) );
	$LayoutLink->setAttribute('Usage','Output');
	$LayoutLink->setAttribute('rRef','Layout'.$Project->id());
	my $RunListLink = $RLP->appendChild( $doc->createElement( 'RunListLink' ) );
	$RunListLink->setAttribute('Usage','Output');
	$RunListLink->setAttribute('ProcessUsage','Marks');
	$RunListLink->setAttribute('rRef','RNL'.$$sig_specs{'SignatureIndex'}.'_Marks');

$openprint::log->debug("Leaveing JDF ImpositionPreparation");	
	return $IP;
} # end sub ImpositionPreparation

sub Assembly {
    my ( $doc, $Project, $sig_id, $sig_specs ) = @_;
$openprint::log->debug("Starting JDF Assembly");	
	my $Assembly = $doc->createElement('Assembly');
    $Assembly->setAttribute('Status','Available');
    $Assembly->setAttribute('Class','Parameter');
	$Assembly->setAttribute('ID', 'ASM100'.$sig_id );
	$Assembly->setAttribute('JogSide', 'Top' );
	if ( $Project->signatures() > 1 ) {
		$Assembly->setAttribute('Order','Collecting');
		$Assembly->setAttribute('BindingSide', 'Left' );
	} else {
		$Assembly->setAttribute('Order','Collecting');
		#$Assembly->setAttribute('Order','List');
	} # end if
$openprint::log->debug("Leaveing JDF Assembly");	
	return $Assembly;
} # end sub Assembly

sub BinderySignature {
	my ( $doc, $Project, $sig_id, $sig_specs ) = @_;
$openprint::log->debug("Starting JDF BinderySignature");	
	my $BinderySignature = $doc->createElement('BinderySignature');
    $BinderySignature->setAttribute('Status','Available');
    $BinderySignature->setAttribute('Class','Parameter');
	my %services = $Project->get_services();
	if ( $services{'Folding'} ) {
		#$BinderySignature->setAttribute('BinderySignatureType','Fold');
		if ( $$sig_specs{'rdbTemplateType'} ) {
			$BinderySignature->setAttribute('FoldCatalog',$folds{$$sig_specs{'rdbTemplateType'}} );
		} else {
			$BinderySignature->setAttribute('FoldCatalog',$folds{$$sig_specs{'PageQuantity'.$Project->ordered_quantity_index()}.'PageFold'} );
		} # end if
	} elsif ( $services{'DieCutting'} ) {
		#$BinderySignature->setAttribute('BinderySignatureType','Die');
	} else {
		#$BinderySignature->setAttribute('BinderySignatureType','Grid');
		my $SignatureCell = $BinderySignature->appendChild( $doc->createElement('SignatureCell') );
		my @side_one_colours = openprint::Estimating::Printing::get_colours( $sig_specs, 'SideOne' );
		my @side_two_colours = openprint::Estimating::Printing::get_colours( $sig_specs, 'SideTwo' );
		if ( @side_one_colours ) {
			$SignatureCell->setAttribute('FrontPages',1);
		} # end if
		if ( @side_two_colours ) {
			$SignatureCell->setAttribute('BackPages',1);
		} # end if
#$SignatureCell->setAttribute('SectionIndex',0);
		$BinderySignature->setAttribute('FoldCatalog',$folds{'NoFold'} );

	} # end if
    #$BinderySignature->setAttribute('NumberUp',join(' ', @$sig_specs{'hdnImpositionColumns'.$Project->ordered_quantity_index(),'hdnImpositionRows'.$Project->ordered_quantity_index()} ) );
	$BinderySignature->setAttribute('ID', 'BIS'.$sig_id );
$openprint::log->debug("Leaveing JDF BinderySignature");	
	return $BinderySignature;
} # end sub BinderySignature

sub StrippingParams {
    my ( $doc, $Project, $sig_id, $sig_specs ) = @_;

$openprint::log->debug("Starting JDF StrippingParams");	

	my $Imposition = new openprint::Imposition();
	$$Imposition{'paper'} = openprint::Paper::load_from_signature( $Project, $sig_specs, $Project->ordered_quantity_index() );
	$Imposition->load( $sig_specs, $Project->ordered_quantity_index() );
	my $Paper = $Imposition->paper();
	my $binding = $Project->get_book_type();


	my $StrippingParams = $doc->createElement('StrippingParams');
    $StrippingParams->setAttribute('Status','Available');
    $StrippingParams->setAttribute('Class','Parameter');
    $StrippingParams->setAttribute('PartIDKeys','SignatureName SheetName');
	$StrippingParams->setAttribute('ID', 'STP'.$sig_id );

	my $SPSignatureName = $StrippingParams->appendChild( $doc->createElement('StrippingParams') );
	$SPSignatureName->setAttribute('SignatureName','Sig#'.$$sig_specs{'SignatureIndex'} );
	my $SPSheetName = $SPSignatureName->appendChild( $doc->createElement('StrippingParams') );
	$SPSheetName->setAttribute('SheetName',sprintf('Sig#%dSheet#%d', $$sig_specs{'SignatureIndex'}, 1 ) );
	$SPSheetName->setAttribute('SectionList','0' );

	my @side_one_colours = openprint::Estimating::Printing::get_colours( $sig_specs, 'SideOne' );
	my @side_two_colours = openprint::Estimating::Printing::get_colours( $sig_specs, 'SideTwo' );
	
	# FIXME Handle Simplex
	if ( @side_one_colours and @side_two_colours ) {
		$SPSheetName->setAttribute('WorkStyle',$runstyles{$Imposition->runstyle()} );
	} else {
		$SPSheetName->setAttribute('WorkStyle','Simplex' );
	} # end if


	my $StripCellParams = $SPSheetName->appendChild( $doc->createElement( 'StripCellParams') );
	$StripCellParams->setAttribute('BleedFace',$$sig_specs{'ddmBleedSize'.$Project->ordered_quantity_index()} * 72);
	$StripCellParams->setAttribute('BleedFoot',$$sig_specs{'ddmBleedSize'.$Project->ordered_quantity_index()} * 72);
	$StripCellParams->setAttribute('BleedHead',$$sig_specs{'ddmBleedSize'.$Project->ordered_quantity_index()} * 72);
#FIX ME PerfectBind has Spine Bleed
	$StripCellParams->setAttribute('TrimFoot',$$sig_specs{'ddmBleedSize'.$Project->ordered_quantity_index()} * 72);
	$StripCellParams->setAttribute('TrimHead',$$sig_specs{'ddmBleedSize'.$Project->ordered_quantity_index()} * 72);
	$$sig_specs{'txtSpreadSize'} = 2 if ! $$sig_specs{'txtSpreadSize'};
	$StripCellParams->setAttribute('TrimSize',join(' ', ($$sig_specs{'txtWidth'}/($$sig_specs{'txtSpreadSize'}/2))*72, $$sig_specs{'txtHeight'}*72 ));
	if ( sets::isin( $binding,['SaddleStitching','LoopStitching'] ) ) {
		$StripCellParams->setAttribute('TrimFace',($$sig_specs{'ddmBleedSize'.$Project->ordered_quantity_index()}) * 72);
		$StripCellParams->setAttribute('BleedSpine',0);
		$StripCellParams->setAttribute('MillingDepth',0);
		$StripCellParams->setAttribute('Spine',0 );
		my $lap = .25 * 72;
		if ( $$sig_specs{'txtSignatureType'} eq 'Cover Pages' ) {
			if ( $Paper->gsm() >= 216 ) { # ROughly 80lb
# Cover doesn't need lap, unless it is off center or under 80lb
				$lap = 0;
			} # end if
		} else {
		} # end if
		$StripCellParams->setAttribute('BackOverfold',0);
		$StripCellParams->setAttribute('FrontOverfold',$lap);
	} elsif ( $binding eq 'PerfectBound' ) {
		$StripCellParams->setAttribute('BleedSpine',$$sig_specs{'ddmBleedSize'.$Project->ordered_quantity_index()} * 72);
		$StripCellParams->setAttribute('MillingDepth',.0.0625);
		$StripCellParams->setAttribute('Spine',0);
		$StripCellParams->setAttribute('BackOverfold',0);
		$StripCellParams->setAttribute('FrontOverfold',0);
	} elsif ( $binding eq 'SpinePaste' ) {
		$StripCellParams->setAttribute('BleedSpine',$$sig_specs{'ddmBleedSize'.$Project->ordered_quantity_index()} * 72);
		$StripCellParams->setAttribute('MillingDepth',.0.0625);
		$StripCellParams->setAttribute('Spine',0);
		$StripCellParams->setAttribute('BackOverfold',0);
	$StripCellParams->setAttribute('FrontOverfold',0);
	} # end if
 
	my $BinderySignatureRef = $SPSheetName->appendChild( $doc->createElement('BinderySignatureRef') );
	$BinderySignatureRef->setAttribute('rRef','BIS'.$sig_id );

	my @Equipment = openprint::Equipment->find( 'strid'=>$$sig_specs{'ddmPress'.$Project->ordered_quantity_index()} );
	my $Equipment = shift @Equipment;
	if ( $Equipment ) {
	my $DeviceRef = $SPSheetName->appendChild( $doc->createElement('DeviceRef') );
		$DeviceRef->setAttribute('rRef','E'.$Equipment->id());
	} # end if


	my $MediaPaper = $SPSheetName->appendChild( $doc->createElement('MediaRef') );
	$MediaPaper->setAttribute('rRef', 'Paper' );
	my $Part = $MediaPaper->appendChild( $doc->createElement('Part') );
	$Part->setAttribute('SignatureName', 'Sig#'.$$sig_specs{'SignatureIndex'} );
	$Part->setAttribute('SheetName',sprintf('Sig#%dSheet#%d', $$sig_specs{'SignatureIndex'}, 1 ) );

	my $MediaPlate = $SPSheetName->appendChild( $doc->createElement('MediaRef') );
	$MediaPlate->setAttribute('rRef', 'PLM'.$Project->id() );
	$Part = $MediaPlate->appendChild( $doc->createElement('Part') );
	$Part->setAttribute('SignatureName', 'Sig#'.$$sig_specs{'SignatureIndex'} );
	$Part->setAttribute('SheetName',sprintf('Sig#%dSheet#%d', $$sig_specs{'SignatureIndex'}, 1 ) );

	my $grip = $Equipment->specification('Grip');
	$grip *= 2 if sets::isin( $Imposition->runstyle(), ['Work & Tumble','Perfecting'] );

	my $columns = $Imposition->columns();
	my $rows = $Imposition->rows();
$Imposition->display();
	my $fold_rotation = '';

	if ( $Imposition->spread_rows() > $Imposition->spread_columns() ) {
		$fold_rotation = 'Rotate90';
	} # end if

	foreach my $col ( 1 .. $columns ) {
		foreach my $row ( 1 .. $rows ) {
			my $Position = $SPSheetName->appendChild( $doc->createElement('Position') );
# Margins are used to do grip, etc..
			if ( $row == 1 ) {
				# Add Grip to margin
			$Position->setAttribute('MarginTop',$grip * 72);
			} else {
			$Position->setAttribute('MarginTop',0);
			} # end if
			$Position->setAttribute('MarginBottom',0);
			$Position->setAttribute('MarginLeft',0);
			$Position->setAttribute('MarginRight',0);
			if ( $Imposition->runstyle() eq 'Work & Turn') {
				if ( $Imposition->image_orientation() == openprint::Imposition::Vertical ) {
					if ($col <= $columns/2) {
						$Position->setAttribute('Orientation', $fold_rotation eq 'Rotate90' ? 'Rotate90' : 'Rotate0');
					} else {
						$Position->setAttribute('Orientation', $fold_rotation eq 'Rotate90' ? 'Flip270' : 'Flip180' );
					} # end if
				} else {
					if ($col <= $columns/2) {
						$Position->setAttribute('Orientation',$fold_rotation eq 'Rotate90' ? 'Flip180' : 'Rotate90');
					} else {
						$Position->setAttribute('Orientation',$fold_rotation eq 'Rotate90' ? 'Rotate0' : 'Flip270');
					} # end if
				} # end if
			} elsif ( $Imposition->runstyle() eq 'Work & Tumble' ) {
				if ( $Imposition->image_orientation() == openprint::Imposition::Vertical ) {
					if ($row <= $rows/2) {
						$Position->setAttribute('Orientation',$fold_rotation eq 'Rotate90' ? 'Rotate90' : 'Rotate0');
					} else {
						$Position->setAttribute('Orientation',$fold_rotation eq 'Rotate90' ? 'Flip270' : 'Flip180');
					} # end if
				} else {
					if ($row <= $rows/2) {
						$Position->setAttribute('Orientation',$fold_rotation eq 'Rotate90' ? 'Flip180' : 'Rotate90');
					} else {
						$Position->setAttribute('Orientation',$fold_rotation eq 'Rotate90' ? 'Rotate0' : 'Flip270');
					} # end if
				} # end if
			} # end if
			$Position->setAttribute('RelativeBox',join(' ', ( ($col-1)/$columns, ($row-1)/$rows, $col/$columns, $row/$rows ) ));
		} # end foreach row
	} # end foreach col
$openprint::log->debug("leaveing JDF StrippingParams");	

	return $StrippingParams;
} # end sub StrippingParams

sub Layout {
    my ( $doc, $Project, $sig_id, $sig_specs, $Imposition, $version ) = @_;

	my $Layout = $doc->createElement('Layout');
	$Layout->setAttribute('Class','Parameter');
	$Layout->setAttribute('Status','Unavailable');
	# Layouts are Partitions
	$Layout->setAttribute('ID','Layout'.$Project->id());
	$Layout->setAttribute('Name','Layout'.$Project->id());
	if ( $version == 1.3 ) {
		$Layout->setAttribute('PartIDKeys','SignatureName SheetName');

		my $Paper = $Imposition->Paper();
		if ( $Paper->width() > $Paper->height() ) {
			$Layout->setAttribute('SurfaceContentsBox',join(' ', 0, 0, $Paper->width()*72, $Paper->height()*72) );
		} else {
			$Layout->setAttribute('SurfaceContentsBox',join(' ', 0, 0, $Paper->height()*72, $Paper->width()*72) );
		} # end if
		$Layout->setAttribute('SourceWorkStyle', $runstyles{$Imposition->runstyle()} );
	
	} # end if
	if ( ( $version < 1.3 ) and $sig_id ) {
		my $Signature = $Layout->appendChild( Layout_Signature( $doc, $Project, $sig_id, $sig_specs, $Imposition, $version ) );
	} # end if

	return $Layout;
}

sub Layout_Signature {
    my ( $doc, $Project, $sig_id, $sig_specs, $Imposition, $version ) = @_;

    my $cell_width = $Imposition->object_width();
    if ( $$sig_specs{'txtSpreadSize'} ) {
        $cell_width /= ($$sig_specs{'txtSpreadSize'}/2);
    } # end if
    my $cell_height = $Imposition->object_height();

    my $Paper = $Imposition->paper();
	my $Layout;
    my $Signature;
    my $Sheet;

	if ( $version == 1.3 ) {
		$Signature = $doc->createElement( 'Layout' );
		$Sheet = $doc->createElement( 'Layout' );
		$Signature->setAttribute('SignatureName','Sig#'.$$sig_specs{'SignatureIndex'} );
		$Sheet->setAttribute('SheetName',sprintf('Sig#%dSheet#%d', $$sig_specs{'SignatureIndex'}, 1 ) );
	} else {
		# Signatures and Sheets are deprecated in 1.3
		$Signature = $doc->createElement( 'Signature' );
		$Signature->setAttribute('Name','Sig#'.$$sig_specs{'SignatureIndex'} );
	
		$Sheet = $Signature->appendChild( $doc->createElement('Sheet') );
		$Sheet->setAttribute('Name','Sheet 1' );

		if ( $Paper->width() > $Paper->height() ) {
			$Sheet->setAttribute('SurfaceContentsBox',join(' ', 0, 0, $Paper->width()*72, $Paper->height()*72) );
		} else {
			$Sheet->setAttribute('SurfaceContentsBox',join(' ', 0, 0, $Paper->height()*72, $Paper->width()*72) );
		} # end if
	} # end if
    my $MediaRef = $Sheet->appendChild( $doc->createElement('MediaRef') );
    $MediaRef->setAttribute( 'rRef', 'Paper' );
    my $Part = $MediaRef->appendChild( $doc->createElement('Part') );
    $Part->setAttribute('SignatureName', 'Sig#'.$$sig_specs{'SignatureIndex'} );
	$Part->setAttribute('SheetName',sprintf('Sig#%dSheet#%d', $$sig_specs{'SignatureIndex'}, 1 ) );

    my @Equipment = openprint::Equipment->find( 'strid'=>$$sig_specs{'ddmPress'.$Project->ordered_quantity_index()} );
    my $Equipment = shift @Equipment;
    my $grip = $Equipment->specification('Grip');

    my $Ord = 0;

	my @side_one_colours = openprint::Estimating::Printing::get_colours( $sig_specs, 'SideOne' );
	my @side_two_colours = openprint::Estimating::Printing::get_colours( $sig_specs, 'SideTwo' );
    my @Surfaces = ('Front');
	if ( $Imposition->runstyle() eq 'Sheet Work' and @side_one_colours and @side_two_colours ) {
        push @Surfaces, 'Back';
    } # end if

    foreach my $surface ( @Surfaces ) {
		# Describes the marks on a sheet surface
        my $Surface = $Sheet->appendChild( $doc->createElement('Surface') );
        $Surface->setAttribute('Side',$surface);

		
        if ( $Paper->width() > $Paper->height() ) {
            $Surface->setAttribute('SurfaceContentsBox',join(' ', 0, 0, $Paper->width()*72, $Paper->height()*72) );
        } else {
            $Surface->setAttribute('SurfaceContentsBox',join(' ', 0, 0, $Paper->height()*72, $Paper->width()*72) );
        } # end if

		if ( $version == 1.3 ) {
			my $MarkObject = $Surface->appendChild( $doc->createElement('MarkObject') );
			$MarkObject->setAttribute('CTM',join(' ', 1,0,0,1,0,0) );
			$MarkObject->setAttribute('Ord', $$sig_specs{'SignatureIndex'}.$Ord);
			$Ord += 1;

			if ( $Paper->width() > $Paper->height() ) {
				$MarkObject->setAttribute('ClipBox',join(' ', 0,0,$Paper->width()*72, $Paper->height()*72 ) );
			} else {
				$MarkObject->setAttribute('ClipBox',join(' ', 0,0,$Paper->height()*72, $Paper->width()*72 ) );
			} # end if

			foreach my $column ( 1 .. $Imposition->columns() ) {
				foreach my $row ( 1 .. $Imposition->rows() ) {
					my $ContentObject = $Surface->appendChild( $doc->createElement('ContentObject') );
					$ContentObject->setAttribute('Ord', $$sig_specs{'SignatureIndex'}.$Ord);
					$Ord += 1;
	# Layouts should generally be centered widthwise for even wear of blanket...
	# # So we need to figure out the side padding...
	# # For now left justify
					if ( $Imposition->image_orientation() == openprint::Imposition::Vertical ) {
						$ContentObject->setAttribute('CTM', '1 0 0 1 0 0');

						my $left = ($column-1) * $Imposition->image_width();
						my $top = ( $row-1) * $Imposition->image_height();
						my $bottom = $top + $Imposition->image_height();
						my $right = $left + $Imposition->image_width();
						$ContentObject->setAttribute('ClipBox', join(' ', ($bottom+$grip)*72, $left*72, ($top+$grip)*72, $right*72 ) );
					} else {
						$ContentObject->setAttribute('CTM', '0 1 -1 0 0 0');
						my $left = ($column-1) * $Imposition->image_height();
						my $top = ( $row-1) * $Imposition->image_width();
						my $bottom = $top + $Imposition->image_width();
						my $right = $left + $Imposition->image_height();
						$ContentObject->setAttribute('ClipBox', join(' ', ($bottom+$grip)*72, $left*72, ($top+$grip)*72, $right*72 ) );
					} # end if
					$ContentObject->setAttribute('TrimSize', join(' ', $cell_width*72, $cell_height*72 ) );
				} # end foreach row
			} # end foreach column
		} # end if version == 1.3
    } # end foreach side
    return $Signature;
} # end sub Layout_Signature

sub JDF_ImpositionIntent {
	my ( $doc, $Project, $sig_id, $sig_specs, $version ) = @_;
	my $ImpositionIntent = $doc->createElement('JDF');
#$ImpositionIntent->setAttribute('xmlns','http://www.cip4.org/JDFSchema_1_1');
	$ImpositionIntent->setAttribute('Status','Waiting');
#$ImpositionIntent->setAttribute('Version','1.2');
#$ImpositionIntent->setAttribute('JobID',$Project->docket());
#$ImpositionIntent->setAttribute('JobPartID',$$sig_specs{'SignatureIndex'} );
	$ImpositionIntent->setAttribute('Type', 'Imposition' );
	$ImpositionIntent->setAttribute('Activation', 'Active' );
	$ImpositionIntent->setAttribute('ID', 'Imposition'.$sig_id );
	my $summary = openprint::service::summary( $Project->id(), $sig_id );
	$summary =~ s/<br\/>/ /g;
	$ImpositionIntent->setAttribute('DescriptiveName', $summary );

	my @Papers = openprint::Paper->find(
			'brand'      => $$sig_specs{'ddmStockBrand'},
			'finish'    => $$sig_specs{'ddmStockFinish'},
			'colour'    => $$sig_specs{'ddmStockColour'},
			'weight'    => $$sig_specs{'ddmStockWeight'},
#'project_type_id'=>$Project->Type()->id(),
			'width'     => $$sig_specs{'StockWidth'.$Project->ordered_quantity_index()},
			'height'    => $$sig_specs{'StockHeight'.$Project->ordered_quantity_index()},
			);
	my $Paper = shift @Papers;
	$Paper = new openprint::Paper() if ! $Paper;
	my $Imposition = new openprint::Imposition();
	$Imposition->paper( $Paper );
	$Imposition->load( $sig_specs, $Project->ordered_quantity_index() );

	my $ResourcePool = $ImpositionIntent->appendChild( $doc->createElement('ResourcePool') );
	my $ResourceLinkPool = $ImpositionIntent->appendChild( $doc->createElement('ResourceLinkPool') );
# Layout
	my $Layout = openprint::JDF::getNode( $doc, 'Layout','ID'=>'Layout'.$Project->id() );
	if ( $Layout ) {
		my $LayoutSignature = $Layout->appendChild( openprint::JDF::Layout_Signature( $doc, $Project, $sig_id, $sig_specs, $Imposition, $version ) );

		my $LayoutLink = $ResourceLinkPool->appendChild( $doc->createElement('LayoutLink') );
		$LayoutLink->setAttribute('Usage','Input');
		$LayoutLink->setAttribute('rRef',$Layout->getAttribute('ID') );
	} # end if Layout

	my $Pages = $$sig_specs{'PageQuantity'.$Project->ordered_quantity_index()};
	$Pages = 2 if ! $Pages;

	{
# Imposition has three parts... or more maybe  input, output and marks(inut)
		my $RunList = $ResourcePool->appendChild( $doc->createElement('RunList') );
		$RunList->setAttribute('ID','RLIn'.$$sig_specs{'SignatureIndex'} );
		$RunList->setAttribute('Class','Parameter');
		$RunList->setAttribute('PartIDKeys','Run');
		$RunList->setAttribute('Status','Available');

		my $RunListRun = $RunList->appendChild( $doc->createElement('RunList') );
		$RunListRun->setAttribute('Status','Unavailable');
		$RunListRun->setAttribute('Pages','0~'.($Pages-1));
		$RunListRun->setAttribute('Run','0');
		my $LayoutElement = $RunListRun->appendChild( $doc->createElement('LayoutElement') );
		$LayoutElement->setAttribute('IsBlank','true');

		my $RunListLink = $ResourceLinkPool->appendChild( $doc->createElement('RunListLink') );
		$RunListLink->setAttribute('Usage','Input');
		$RunListLink->setAttribute('ProcessUsage','Document');
		$RunListLink->setAttribute('rRef','RLIn'.$$sig_specs{'SignatureIndex'} );
	} 
	{
		my $RunList = $ResourcePool->appendChild( $doc->createElement('RunList') );
		$RunList->setAttribute('ID','RLMarks'.$$sig_specs{'SignatureIndex'} );
		$RunList->setAttribute('Class','Parameter');
		$RunList->setAttribute('PartIDKeys','Run');
		$RunList->setAttribute('Status','Available');
		my $RunListRun = $RunList->appendChild( $doc->createElement('RunList') );
		$RunListRun->setAttribute('Status','Unavailable');
		$RunListRun->setAttribute('Pages','0~'.($Pages-1));
		$RunListRun->setAttribute('Run','0');
		my $LayoutElement = $RunListRun->appendChild( $doc->createElement('LayoutElement') );
		$LayoutElement->setAttribute('IsBlank','true');

		my $RunListLink = $ResourceLinkPool->appendChild( $doc->createElement('RunListLink') );
		$RunListLink->setAttribute('Usage','Input');
		$RunListLink->setAttribute('ProcessUsage','Marks');
		$RunListLink->setAttribute('rRef','RLMarks'.$$sig_specs{'SignatureIndex'} );
	}

	my $RunList = $ResourcePool->appendChild( $doc->createElement('RunList') );
	$RunList->setAttribute('ID','RLOut'.$$sig_specs{'SignatureIndex'} );
	$RunList->setAttribute('Class','Parameter');
	$RunList->setAttribute('PartIDKeys','Run');
	$RunList->setAttribute('Status','Available');
	my $RunListRun = $RunList->appendChild( $doc->createElement('RunList') );
	$RunListRun->setAttribute('Status','Unavailable');
	$RunListRun->setAttribute('Pages','0~'.($Pages-1));
	$RunListRun->setAttribute('Run','0');
	my $LayoutElement = $RunListRun->appendChild( $doc->createElement('LayoutElement') );
	$LayoutElement->setAttribute('IsBlank','true');

	my $OutputRunListLink = $ResourceLinkPool->appendChild( $doc->createElement('RunListLink') );
	$OutputRunListLink->setAttribute('Usage','Output');
	$OutputRunListLink->setAttribute('rRef','RLOut'.$$sig_specs{'SignatureIndex'} );

	return $ImpositionIntent;
} # end sub JDF_ImpositionIntent

sub JDF_SignatureIntent {
    my ( $doc, $Project, $sig_id, $sig_specs, $version ) = @_;
    my $project = $doc->createElement('JDF');
    #$project->setAttribute('xmlns','http://www.cip4.org/JDFSchema_1_1');
    $project->setAttribute('Status','Waiting');
    #$project->setAttribute('Activation','Active');
    #$project->setAttribute('Version','1.2');
    #$project->setAttribute('JobID',$Project->docket());
    $project->setAttribute('JobPartID','Signature'.$$sig_specs{'SignatureIndex'} );
    $project->setAttribute('Type', 'Product' );
    $project->setAttribute('xsi:type', 'Product' );
    $project->setAttribute('ID', 'Signature'.$sig_id );
	#my $summary = openprint::service::summary( $Project->id(), $sig_id );
	#$summary .= openprint::service::summary( $Project->id(), $sig_id, $Project->ordered_quantity_index() );
	#$summary =~ s/<br\/>/ /g;
	$project->setAttribute('DescriptiveName', $$sig_specs{'txtServiceDescription'} );

    my $ResourcePool = $project->appendChild( $doc->createElement('ResourcePool') );
    my $ResourceLinkPool = $project->appendChild( $doc->createElement('ResourceLinkPool') );

$openprint::log->debug("Before load from signature");
	my $Paper = openprint::Paper::load_from_signature( $Project, $sig_specs );
$openprint::log->debug("After load from signature");
if ( 1 ) {
# Paper
	$ResourcePool->appendChild( $Paper->JDF_MediaIntent( $doc, $$sig_specs{'SignatureIndex'} ) );

	my $MediaLink = $ResourceLinkPool->appendChild( $doc->createElement('MediaIntentLink'));
	$MediaLink->setAttribute('Usage','Input' );
	$MediaLink->setAttribute('rRef','Paper'.$$sig_specs{'SignatureIndex'} );
}
	my $Imposition = new openprint::Imposition();
	$Imposition->paper( $Paper );
	$Imposition->load( $sig_specs, $Project->ordered_quantity_index() );

	my $Layout = openprint::JDF::getNode( $doc, 'Layout' );
	my $LayoutSignature = $Layout->appendChild( Layout_Signature( $doc, $Project, $sig_id, $sig_specs, $Imposition, $version ) ) if $Layout;
	#my $LayoutLink = $ResourceLinkPool->appendChild( $doc->createElement('LayoutLink') );
	#$LayoutLink->setAttribute('Usage','Input');
	#$LayoutLink->setAttribute('rRef',$Layout->getAttribute('ID') );

	#my $ArtDeliveryIntent = $ResourcePool->appendChild($doc->createElement('ArtDeliveryIntent'));
    #$ArtDeliveryIntent->setAttribute('Class','Intent');
    #$ArtDeliveryIntent->setAttribute('ID','ADI'.$sig_id);
    #$ArtDeliveryIntent->setAttribute('Status','Available');
    #$ArtDeliveryIntent->setAttribute('rRefs','');

	my @side_one_colours = openprint::Estimating::Printing::get_colours( $sig_specs, 'SideOne' );
	my @side_two_colours = openprint::Estimating::Printing::get_colours( $sig_specs, 'SideTwo' );
if ( 1 ) {
	my $LayoutIntent = $ResourcePool->appendChild($doc->createElement('LayoutIntent'));
	$LayoutIntent->setAttribute('Class','Intent');
	$LayoutIntent->setAttribute('Status','Available');
	$LayoutIntent->setAttribute('ID','L'.$sig_id);

	if ( @side_one_colours and @side_two_colours ) { 
		$LayoutIntent->setAttribute('Sides', 'TwoSidedHeadToHead' );
# There is also TwoSidedHeadToFoot
	} elsif ( @side_one_colours ) {
		$LayoutIntent->setAttribute('Sides', 'OneSided' );
	} elsif ( @side_two_colours ) {
		$LayoutIntent->setAttribute('Sides', 'OneSidedBack' );
	}  # end if
	#my $Dimensions = $LayoutIntent->appendChild($doc->createElement('Dimensions'));
	#$Dimensions->setAttribute('DataType','ShapeSpan');
	#$Dimensions->setAttribute('Preferred',join(' ', 
				##$$sig_specs{'txtWidth'}*72,
				#$$sig_specs{'txtHeight'}*72,
				#0
				#) );
	if ( $$sig_specs{'txtFinalWidth'} and $$sig_specs{'txtFinalHeight'} ) {
		my $FinishedDimensions = $LayoutIntent->appendChild($doc->createElement('FinishedDimensions'));
		$FinishedDimensions->setAttribute('DataType','ShapeSpan');
		$FinishedDimensions->setAttribute('Preferred',join(' ', 
					$$sig_specs{'txtFinalWidth'}*72,
					$$sig_specs{'txtFinalHeight'}*72,
					0
					) );
		$FinishedDimensions->setAttribute('Actual',join(' ', 
					$$sig_specs{'txtFinalWidth'}*72,
					$$sig_specs{'txtFinalHeight'}*72,
					0
					) );
	} # end if
	if ( $$sig_specs{'PageQuantity'.$Project->ordered_quantity_index()} ) {
		my $Pages = $LayoutIntent->appendChild( $doc->createElement('Pages'));
		$Pages->setAttribute('DataType','IntegerSpan');
		$Pages->setAttribute('Actual',$$sig_specs{'pageQuantity'.$Project->ordered_quantity_index()});
		$Pages->setAttribute('Preferred',$$sig_specs{'PageQuantity'.$Project->ordered_quantity_index()});
	} # end if
	
	my $LayoutIntentLink  = $ResourceLinkPool->appendChild( $doc->createElement('LayoutIntentLink') );
	$LayoutIntentLink->setAttribute('Usage','Input');
	$LayoutIntentLink->setAttribute('rRef','L'.$sig_id);

	my $ColorIntent = $ResourcePool->appendChild($doc->createElement('ColorIntent'));
	$ColorIntent->setAttribute('Class','Intent');
	$ColorIntent->setAttribute('Status','Available');
	$ColorIntent->setAttribute('ID','CI'.$sig_id);
	$ColorIntent->setAttribute('PartIDKeys','Side');
	if ( @side_one_colours ) {
		my $FrontColorIntent = $ColorIntent->appendChild($doc->createElement('ColorIntent'));
		$FrontColorIntent->setAttribute('Side','Front');
		my $ColorsUsed = $FrontColorIntent->appendChild($doc->createElement('ColorsUsed'));
		foreach my $color ( @side_one_colours ) {
			my $SeparationSpec = $ColorsUsed->appendChild($doc->createElement('SeparationSpec'));
			$SeparationSpec->setAttribute('Name',$color);
		} # end foreach
	}
	if ( @side_two_colours ) {
		my $BackColorIntent = $ColorIntent->appendChild($doc->createElement('ColorIntent'));
		$BackColorIntent->setAttribute('Side','Back');
		my $ColorsUsed = $BackColorIntent->appendChild($doc->createElement('ColorsUsed'));
		foreach my $color ( @side_two_colours ) {
			my $SeparationSpec = $ColorsUsed->appendChild($doc->createElement('SeparationSpec'));
			$SeparationSpec->setAttribute('Name',$color);
		} # end foreach
	}

	my $ColorStandard = $ColorIntent->appendChild($doc->createElement('ColorStandard'));
	$ColorStandard->setAttribute('DataType','NameSpan');
	$ColorStandard->setAttribute('Preferred','CMYK');

	my $ColorIntentLink = $ResourceLinkPool->appendChild( $doc->createElement('ColorIntentLink') );
	$ColorIntentLink->setAttribute('Usage','Input');
	$ColorIntentLink->setAttribute('rRef','CI'.$sig_id);
	
}  # end if
    my %services = $Project->get_services();
    my $printing_specs = openprint::service::get_specs_ref( $Project->id(), $services{''}[0] );
	# Metrix Components
if ( 0 ) {
	my $Component = $ResourcePool->appendChild( $doc->createElement('Component') );
	$Component->setAttribute('Class','Quantity');
	$Component->setAttribute('ComponentType','PartialProduct Sheet');
	$Component->setAttribute('DescriptiveName','IDUNNO');
	$Component->setAttribute('ID','ConvPrint'.$sig_id);
	$Component->setAttribute('Dimensions',join(' ', $Paper->width()*72,$Paper->height()*72,0));
	$Component->setAttribute('PartIDKeys','SignatureName SheetName Condition');
	if ( $version == 1.2 ) {
	$Component->setAttribute('SourceSheet','Sheet 1');
	} # end if
	$Component->setAttribute('Status','Unavailable');
	my $LayoutRef = $Component->appendChild( $doc->createElement('LayoutRef' ) );
	$LayoutRef->setAttribute('rRef',$Layout->getAttribute('ID') );
	my $SignatureNameComponent = $Component->appendChild( $doc->createElement('Component') );
	$SignatureNameComponent->setAttribute('SignatureName','Sig#'.$$sig_specs{'SignatureIndex'} );
	my $SheetNameComponent = $SignatureNameComponent->appendChild( $doc->createElement('Component') );
	$SheetNameComponent->setAttribute('SheetName',sprintf('Sig#%dSheet#%d', $$sig_specs{'SignatureIndex'}, 1 ) );
	my $ConditionGoodComponent = $SheetNameComponent->appendChild( $doc->createElement('Component') );
	$ConditionGoodComponent->setAttribute('Condition','Good');
	$ConditionGoodComponent->setAttribute('IsWaste','false');
	my $ConditionWasteComponent = $SheetNameComponent->appendChild( $doc->createElement('Component') );
	$ConditionWasteComponent->setAttribute('Condition','Waste');
	$ConditionWasteComponent->setAttribute('IsWaste','true');

	my $OutputComponent = $ResourcePool->appendChild( $doc->createElement('Component') );
	$OutputComponent->setAttribute('ID','PS'.$$sig_specs{'SignatureIndex'} );
	$OutputComponent->setAttribute('Class','Quantity' );
	$OutputComponent->setAttribute('ComponentType','PartialProduct Sheet' );
	$OutputComponent->setAttribute('DescriptiveName',$$sig_specs{'txtSignatureType'} );
	$OutputComponent->setAttribute('Dimensions',join(' ', $Paper->width()*72,$Paper->height()*72,0));
	$OutputComponent->setAttribute('ProductType', openprint::JDF::ProductType( $Project, $sig_specs ) );
	$OutputComponent->setAttribute('Status','Unavailable' );
	} # end if
	

	my $OutputComponentLink = $ResourceLinkPool->appendChild( $doc->createElement('ComponentLink') );
	$OutputComponentLink->setAttribute('Usage','Output');
	$OutputComponentLink->setAttribute('Amount',$$sig_specs{'txtQuantity'.$Project->ordered_quantity_index()});
	$OutputComponentLink->setAttribute('rRef','SUB'.$$sig_specs{'SignatureIndex'} );
	#my $Part = $OutputComponentLink->appendChild( $doc->createElement( 'Part' ) );
	#$Part->setAttribute('SignatureName','Sig#'.$$sig_specs{'SignatureIndex'});
	#$Part->setAttribute('SheetName','Sig#'.$$sig_specs{'SignatureIndex'}. 'Sheet#1');
	return $project;
} # end sub SignatureIntent

# Generates JDF for a signature...
sub JDF_PrintingGreyBox {
    my ( $doc, $Project, $sig_id, $sig_specs, $version ) = @_;
$openprint::log->debug("Start JDF_PrintingGreyBox");
    my $project = $doc->createElement('JDF');
    $project->setAttribute('Status','Waiting');
    $project->setAttribute('JobPartID',$Project->id() . '#' . $sig_id );
    $project->setAttribute('Type', 'ProcessGroup' );
    $project->setAttribute('Types', 'InkZoneCalculation ConventionalPrinting' );
    $project->setAttribute('ID', 'CP'.$sig_id );
	$project->setAttribute('Category','Printing');
	$project->setAttribute('DescriptiveName','Printing ' . $$sig_specs{'txtServiceDescription'} );


	my $TopResourcePool = openprint::JDF::getNode( $doc, 'ResourcePool' );
    my $ResourcePool = $project->appendChild( $doc->createElement('ResourcePool') );
    my $ResourceLinkPool = $project->appendChild( $doc->createElement('ResourceLinkPool') );
	my $NodeInfo = JDF_NodeInfo( $doc, $Project, $sig_id, $sig_specs, $version, $project, $ResourcePool, $ResourceLinkPool );
	my $PrintingParam = JDF_ConventionalPrintingParams( $doc, $Project, $sig_id, $sig_specs, $version, $ResourcePool, $ResourceLinkPool );
	my $Component = JDF_Component( $doc, $Project, $sig_id, $sig_specs, $version, $TopResourcePool, $ResourceLinkPool );

	my $Paper = openprint::Paper::load_from_signature( $Project, $sig_specs );
	if ( $Paper ) {
# Paper
		JDF_PaperIntent( $doc, $sig_specs, $Paper, $version, $TopResourcePool, $ResourceLinkPool );
	} # end if
	my $PlateIntent = JDF_PlateIntent( $doc, $Project, $sig_id, $sig_specs, $version, $TopResourcePool, $ResourceLinkPool );
	my $ExposedMedia = JDF_ExposedMedia( $doc, $Project, $sig_id, $sig_specs, $version, $TopResourcePool, $ResourceLinkPool );
	
	# Add Press?
	my $Equipment;
	if ( $$sig_specs{'UsePress'} ) {
		my @Equipment = openprint::Equipment->find('strid'=>$$sig_specs{'UsePress'});
		$Equipment = shift @Equipment if @Equipment;
	} else {
		my @Equipment = openprint::Equipment->find('strid'=>$$sig_specs{'ddmPress'.$Project->ordered_quantity_index()} );
		$Equipment = shift @Equipment if @Equipment;
	} # end if
	if ( $Equipment ) {
		my $Device = JDF_Device( $doc, $Equipment, $version, $TopResourcePool, $ResourceLinkPool );
	} # end if
	
	my $ColorantControl = JDF_ColorantControl( $doc, $Project, $sig_id, $sig_specs, $version, $TopResourcePool, $ResourceLinkPool );
	# Ink
	my $InkLink = $ResourceLinkPool->appendChild( $doc->createElement('InkLink'));
	$InkLink->setAttribute('Usage','Input' );
	$InkLink->setAttribute('rRef','INK');
	my $Part = $InkLink->appendChild( $doc->createElement('Part'));
	$Part->setAttribute('SheetName',sprintf('Sig#%dSheet#%d', $$sig_specs{'SignatureIndex'}, 1 ) );
	$Part->setAttribute('SignatureName','Sig#'.$$sig_specs{'SignatureIndex'});

	my $Layout = openprint::JDF::getNode( $doc, 'Layout', 'ID'=>'Layout'.$Project->id() );
	if ( $Layout ) {
		my $LayoutLink = $ResourceLinkPool->appendChild( $doc->createElement('LayoutLink') );
		$LayoutLink->setAttribute('Usage','Input');
		$LayoutLink->setAttribute('rRef',$Layout->getAttribute('ID') );
		if ( $version == 1.3 ) {
			my $Part = $LayoutLink->appendChild( $doc->createElement('Part'));
			$Part->setAttribute('SheetName',sprintf('Sig#%dSheet#%d', $$sig_specs{'SignatureIndex'}, 1 ) );
			$Part->setAttribute('SignatureName','Sig#'.$$sig_specs{'SignatureIndex'});
		} # end if
	} # end if Layout
	return $project;
} # end sub JDF_PrintingGreyBox

sub JDF_NodeInfo {
	my ( $doc, $Project, $sig_id, $sig_specs, $version, $Parent, $ResourcePool, $ResourceLinkPool ) = @_;
	my $NodeInfo = $doc->createElement('NodeInfo');;
	if ( $version == 1.3 ) {
		$NodeInfo = $ResourcePool->appendChild( $doc->createElement('NodeInfo') );
	$NodeInfo->setAttribute('ID','NI'.$sig_id);
	$NodeInfo->setAttribute('Class','Parameter');
	$NodeInfo->setAttribute('Status','Available');
	} else {
		$NodeInfo = $Parent->appendChild( $doc->createElement('NodeInfo') );
	} # end if
	my $time = openprint::Estimating::Printing::runtime( $Project,$sig_specs );
	
	$NodeInfo->setAttribute('SetupDuration','PT'.misc::seconds_to_JDF_interval( $$time{'Setup'} ));
	$NodeInfo->setAttribute('TotalDuration','PT'.misc::seconds_to_JDF_interval( $$time{'Total'} ));
	#$NodeInfo->setAttribute('Class','Parameter');
	#$NodeInfo->setAttribute('Status','Available');
	$NodeInfo->setAttribute('JobPriority','50');

	if ( $version == 1.3 ) {
		my $NodeInfoLink = $ResourceLinkPool->appendChild( $doc->createElement('NodeInfoLink') );
		$NodeInfoLink->setAttribute('rRef','NI'.$sig_id);
		$NodeInfoLink->setAttribute('Usage','Input');
	} # end if
	return $NodeInfo;
} # end sub JF_NodeInfo

sub JDF_ConventionalPrintingParams {
    my ( $doc, $Project, $sig_id, $sig_specs, $version, $ResourcePool, $ResourceLinkPool ) = @_;
	
	my $PrintingParam = $ResourcePool->appendChild( $doc->createElement('ConventionalPrintingParams' ) );
	$PrintingParam->setAttribute('Class','Parameter');
	$PrintingParam->setAttribute('DescriptiveName','Printing Setup');
	$PrintingParam->setAttribute('ID','PP'.$sig_id);
	#$PrintingParam->setAttribute( 'Locked', 'false' );
	$PrintingParam->setAttribute('PrintingType','SheetFed');
	if ( ! $$sig_specs{'ddmRunStyle'.$Project->ordered_quantity_index()} ) {
		$PrintingParam->setAttribute('WorkStyle', $openprint::JDF::runstyles{$$sig_specs{'ddmRunStyle'}} );
	} else {
		$PrintingParam->setAttribute('WorkStyle', $openprint::JDF::runstyles{$$sig_specs{'ddmRunStyle'.$Project->ordered_quantity_index()}} );
	} # end if
	$PrintingParam->setAttribute( 'Status', 'Incomplete' );

	my $ConventionalPrintingParamsLink = $ResourceLinkPool->appendChild( $doc->createElement('ConventionalPrintingParamsLink'));
	$ConventionalPrintingParamsLink->setAttribute('Usage','Input' );
	$ConventionalPrintingParamsLink->setAttribute('rRef','PP'.$sig_id);

	return $PrintingParam;
} # end sub JDF_ConventionalPrintingParams

sub JDF_Component {
    my ( $doc, $Project, $sig_id, $sig_specs, $version, $ResourcePool, $ResourceLinkPool ) = @_;

	my $Component = openprint::JDF::getNode($ResourcePool, 'Component', 'ID'=>'PS'.$Project->id());
	if ( ! $Component ) {
		$Component = $ResourcePool->appendChild( $doc->createElement('Component') );
		$Component->setAttribute('ID', 'PS'.$$sig_specs{'SignatureIndex'} );
		$Component->setAttribute('Class', 'Quantity');
		$Component->setAttribute('ComponentType', 'Sheet');
		$Component->setAttribute('DescriptiveName', 'Output after Printing' );
		$Component->setAttribute('Status','Unavailable');
		#$Component->setAttribute( 'Dimensions',join(' ',
					#$$sig_specs{'StockWidth'.$Project->ordered_quantity_index()}*72,
					#$$sig_specs{'StockHeight'.$Project->ordered_quantity_index()}*72,
					#$$sig_specs{'txtSpecificStockCalliper'} * 72,
					#) );
		$Component->setAttribute('ProductType', 'PrintedSheet');
		#$Component->setAttribute('IsWaste', 'false');
		$Component->setAttribute('PartIDKeys', 'SignatureName SheetName Condition');
	} # end if $Component
	my $ComponentSignatureName = $Component->appendChild( $doc->createElement('Component') );
	$ComponentSignatureName->setAttribute('SignatureName','Sig#'.$$sig_specs{'SignatureIndex'});
	$ComponentSignatureName->setAttribute('ProductType', openprint::JDF::ProductType( $Project, $sig_specs ) );
	my $ComponentSheetName = $ComponentSignatureName->appendChild( $doc->createElement('Component') );
	$ComponentSheetName->setAttribute('SheetName',sprintf('Sig#%dSheet#%d', $$sig_specs{'SignatureIndex'}, 1 ) );
	my $ComponentConditionGood = $ComponentSheetName->appendChild( $doc->createElement('Component') );
	$ComponentConditionGood->setAttribute('IsWaste','false');
	$ComponentConditionGood->setAttribute('Condition','Good');
	my $ComponentConditionWaste = $ComponentSheetName->appendChild( $doc->createElement('Component') );
	$ComponentConditionWaste->setAttribute('IsWaste','true');
	$ComponentConditionWaste->setAttribute('Condition','Waste');

	my $ComponentLink = $ResourceLinkPool->appendChild( $doc->createElement('ComponentLink'));
	$ComponentLink->setAttribute('Usage','Output');
	$ComponentLink->setAttribute('rRef','PS'.$$sig_specs{'SignatureIndex'});
	$ComponentLink->setAttribute('Amount',$$sig_specs{'hdnGrossSheetCount'.$Project->ordered_quantity_index()} );
	my $GoodPart = $ComponentLink->appendChild( $doc->createElement('Part'));
	$GoodPart->setAttribute('SheetName',sprintf('Sig#%dSheet#%d', $$sig_specs{'SignatureIndex'}, 1 ) );
	$GoodPart->setAttribute('SignatureName','Sig#'.$$sig_specs{'SignatureIndex'});
	$GoodPart->setAttribute('Condition','Good');
	my $WastePart = $ComponentLink->appendChild( $doc->createElement('Part'));
	$WastePart->setAttribute('SheetName',sprintf('Sig#%dSheet#%d', $$sig_specs{'SignatureIndex'}, 1 ) );
	$WastePart->setAttribute('SignatureName','Sig#'.$$sig_specs{'SignatureIndex'});
	$WastePart->setAttribute('Condition','Waste');

	my $AmountPool = $ComponentLink->appendChild( $doc->createElement('AmountPool'));
	my $GoodPartAmount = $AmountPool->appendChild( $doc->createElement('PartAmount'));
	$GoodPartAmount->setAttribute('Amount',$$sig_specs{'hdnNetSheetCount'.$Project->ordered_quantity_index()} );

	$GoodPart = $GoodPartAmount->appendChild( $doc->createElement('Part'));
	$GoodPart->setAttribute('SheetName',sprintf('Sig#%dSheet#%d', $$sig_specs{'SignatureIndex'}, 1 ) );
	$GoodPart->setAttribute('SignatureName','Sig#'.$$sig_specs{'SignatureIndex'});
	$GoodPart->setAttribute('Condition','Good');

	my $WastePartAmount = $AmountPool->appendChild( $doc->createElement('PartAmount'));
	$WastePartAmount->setAttribute('Amount',
		$$sig_specs{'hdnGrossSheetCount'.$Project->ordered_quantity_index()} -
		$$sig_specs{'hdnNetSheetCount'.$Project->ordered_quantity_index()}
	 );

	$WastePart = $WastePartAmount->appendChild( $doc->createElement('Part'));
	$WastePart->setAttribute('SheetName',sprintf('Sig#%dSheet#%d', $$sig_specs{'SignatureIndex'}, 1 ) );
	$WastePart->setAttribute('SignatureName','Sig#'.$$sig_specs{'SignatureIndex'});
	$WastePart->setAttribute('Condition','Waste');

	return $Component;
} # end sub JDF_Component

sub JDF_PlateIntent {
    my ( $doc, $Project, $sig_id, $sig_specs, $version, $ResourcePool ) = @_;

	my $PlateIntent = openprint::JDF::getNode( $doc, 'Media','MediaType'=>'Plate','ID'=>'PLM'.$Project->id() );
	if ( ! $PlateIntent ) {
	# PLates
		$PlateIntent = $ResourcePool->appendChild( $doc->createElement('Media') );
		$PlateIntent->setAttribute('ID','PLM'.$Project->id());
	#$PlateIntent->setAttribute('Brand','Agfa' );
		$PlateIntent->setAttribute('ProductID','PLM'.$Project->id() );
		$PlateIntent->setAttribute('Class','Consumable' );
	#$PlateIntent->setAttribute('Dimension',join(' ', (1*$Equipment->specification('Plate Size'))*72, 28*72 ) );
	#$PlateIntent->setAttribute('Locked','false' );
		$PlateIntent->setAttribute('MediaType','Plate' );
		$PlateIntent->setAttribute('Status','Available' );
		$PlateIntent->setAttribute('PartIDKeys','SignatureName SheetName');
	} # end if
	my $PlateIntentSignatureName = $PlateIntent->appendChild( $doc->createElement('Media' ));
	$PlateIntentSignatureName->setAttribute('SignatureName','Sig#'.$$sig_specs{'SignatureIndex'} );
	my $PlateIntentSheetName = $PlateIntentSignatureName->appendChild( $doc->createElement('Media' ));
	$PlateIntentSheetName->setAttribute('SheetName',sprintf('Sig#%dSheet#%d', $$sig_specs{'SignatureIndex'}, 1 ) );

	return $PlateIntent;
} # end sub JDF_PlateIntent

sub JDF_ExposedMedia {
    my ( $doc, $Project, $sig_id, $sig_specs, $version, $ResourcePool, $ResourceLinkPool ) = @_;

	my $ExposedMedia = openprint::JDF::getNode( $ResourcePool, 'ExposedMedia', 'ID'=>'PL'.$Project->id() );
	if ( ! $ExposedMedia ) {	
		$ExposedMedia = $ResourcePool->appendChild( $doc->createElement( 'ExposedMedia' ) );
		$ExposedMedia->setAttribute('ID','PL'.$Project->id());
		$ExposedMedia->setAttribute('Class','Handling');
		#$ExposedMedia->setAttribute('Locked','true');
		$ExposedMedia->setAttribute('Status','Unavailable');
		$ExposedMedia->setAttribute('DescriptiveName','Plates');
		$ExposedMedia->setAttribute('PartIDKeys','SignatureName SheetName Side Separation');
	} # end if
	#my $ExposedMediaSignatureName = $ExposedMedia->appendChild( $doc->createElement( 'ExposedMedia' ) );
	#$ExposedMediaSignatureName->setAttribute('SignatureName','Sig#'.$$sig_specs{'SignatureIndex'} );
	#my $ExposedMediaSheetName = $ExposedMediaSignatureName->appendChild( $doc->createElement( 'ExposedMedia' ) );
	#$ExposedMediaSheetName->setAttribute('SheetName','Sig#'.$$sig_specs{'SignatureIndex'}.'Sheet#1' );

	my @side_one_colours = openprint::Estimating::Printing::get_colours( $sig_specs, 'SideOne' );
	my @side_two_colours = openprint::Estimating::Printing::get_colours( $sig_specs, 'SideTwo' );

	my $ExposedMediaSignatureName = $ExposedMedia->appendChild( $doc->createElement( 'ExposedMedia' ) );
	$ExposedMediaSignatureName->setAttribute('SignatureName','Sig#'.$$sig_specs{'SignatureIndex'} );
	my $ExposedMediaSheetName = $ExposedMediaSignatureName->appendChild( $doc->createElement( 'ExposedMedia' ) );
	$ExposedMediaSheetName->setAttribute('SheetName',sprintf('Sig#%dSheet#%d', $$sig_specs{'SignatureIndex'}, 1 ) );
	#$ExposedMediaSheetName->setAttribute('Locked','false');
	my $plate_index = 1;
	if ( @side_one_colours ) {
		my $ExposedMediaFront = $ExposedMediaSheetName->appendChild( $doc->createElement( 'ExposedMedia' ) );	
		$ExposedMediaFront->setAttribute('Side','Front');
		foreach my $colour ( @side_one_colours ) {
			my $Colour = $ExposedMediaFront->appendChild( $doc->createElement( 'ExposedMedia' ) );
			$Colour->setAttribute('Separation',$colour);
			$Colour->setAttribute('ProductID',sprintf('pl%d.%d',, $$sig_specs{'SignatureIndex'}, $plate_index ) );
			$plate_index += 1;
		} # end foreach
		my $MediaRef = $ExposedMediaFront->appendChild( $doc->createElement('MediaRef' ));
		$MediaRef->setAttribute('rRef','PLM'.$Project->id());
		my $Part = $MediaRef->appendChild($doc->createElement('Part'));
		$Part->setAttribute('SignatureName', 'Sig#'.$$sig_specs{'SignatureIndex'} );
		$Part->setAttribute('SheetName',sprintf('Sig#%dSheet#%d', $$sig_specs{'SignatureIndex'}, 1 ) );
	} # end if
	if ( @side_two_colours ) {
		my $ExposedMediaBack = $ExposedMediaSheetName->appendChild( $doc->createElement( 'ExposedMedia' ) );	
		$ExposedMediaBack->setAttribute('Side','Back');
		foreach my $colour ( @side_two_colours ) {
			my $Colour = $ExposedMediaBack->appendChild( $doc->createElement( 'ExposedMedia' ) );
			$Colour->setAttribute('Separation',$colour);
			$Colour->setAttribute('ProductID',sprintf('pl%d.%d',, $$sig_specs{'SignatureIndex'}, $plate_index ) );
			$plate_index += 1;
		} # end foreach
		my $MediaRef = $ExposedMediaBack->appendChild( $doc->createElement('MediaRef' ));
		$MediaRef->setAttribute('rRef','PLM'.$Project->id());
		my $Part = $MediaRef->appendChild($doc->createElement('Part'));
		$Part->setAttribute('SignatureName', 'Sig#'.$$sig_specs{'SignatureIndex'} );
		$Part->setAttribute('SheetName',sprintf('Sig#%dSheet#%d', $$sig_specs{'SignatureIndex'}, 1 ) );
	} # end if

	my $ExposedMediaLink = $ResourceLinkPool->appendChild( $doc->createElement('ExposedMediaLink') );
	$ExposedMediaLink->setAttribute('ProcessUsage','Plate');
	$ExposedMediaLink->setAttribute('Usage','Input');
	$ExposedMediaLink->setAttribute('rRef','PL'.$Project->id());
	my $Part = $ExposedMediaLink->appendChild( $doc->createElement('Part') );
	$Part->setAttribute('SheetName',sprintf('Sig#%dSheet#%d', $$sig_specs{'SignatureIndex'}, 1 ) );
	$Part->setAttribute('SignatureName','Sig#'.$$sig_specs{'SignatureIndex'});
	return $ExposedMedia;
} # end sub JDF_ExposedMedia

sub JDF_ColorantControl {
    my ( $doc, $Project, $sig_id, $sig_specs, $version, $ResourcePool, $ResourceLinkPool ) = @_;

	my $ColorantControl = $ResourcePool->appendChild( $doc->createElement( 'ColorantControl') );
	$ColorantControl->setAttribute('Class','Parameter');
	#$ColorantControl->setAttribute('Locked','false');
	$ColorantControl->setAttribute('PartIDKeys','SignatureName SheetName Side');
	$ColorantControl->setAttribute('Status','Available');
	$ColorantControl->setAttribute('ProcessColorModel','DeviceCMYK');
	$ColorantControl->setAttribute('ID','CC'.$$sig_specs{'SignatureIndex'} );

	my @side_one_colours = openprint::Estimating::Printing::get_colours( $sig_specs, 'SideOne' );
	my @side_two_colours = openprint::Estimating::Printing::get_colours( $sig_specs, 'SideTwo' );

	my $ColourPoolRef = $ColorantControl->appendChild( $doc->createElement( 'ColorPoolRef') );
	$ColourPoolRef->setAttribute('rRef','CP' );
	my $ColorantParams = $ColorantControl->appendChild( $doc->createElement( 'ColorantParams') );
	foreach my $colour (@side_one_colours, @side_two_colours) {
		next if sets::isin( $colour , ['Cyan','Magenta','Yellow','Black'] );
		my $SeparationSpec = $ColorantParams->appendChild( $doc->createElement( 'SeparationSpec') );
		$SeparationSpec->setAttribute('Name',$colour);
	} # end foreach
	
	my %SideColours = (
		'Front'=>\@side_one_colours,
		'Back'=>\@side_two_colours,
		);

	my $ColorantControlSig = $ColorantControl->appendChild( $doc->createElement( 'ColorantControl') );
	$ColorantControlSig->setAttribute('SignatureName', 'Sig#'.$$sig_specs{'SignatureIndex'} );

	my $ColorantControlSheet = $ColorantControlSig->appendChild( $doc->createElement( 'ColorantControl') );
	$ColorantControlSheet->setAttribute('SheetName',sprintf('Sig#%dSheet#%d', $$sig_specs{'SignatureIndex'}, 1 ) );

	foreach my $side ( 'Front','Back' ) {
		my $ColorantControlSide = $ColorantControlSheet->appendChild( $doc->createElement( 'ColorantControl') );
		$ColorantControlSide->setAttribute('Side',$side);
		my $ColorantOrder = $ColorantControlSide->appendChild( $doc->createElement( 'ColorantOrder') );
		foreach my $colour (@{$SideColours{$side}}) {
			my $SeparationSpec = $ColorantOrder->appendChild( $doc->createElement( 'SeparationSpec') );
			$SeparationSpec->setAttribute('Name',$colour);
		} # end foreach
	} # end foreach

	my $ColorPool = openprint::JDF::getNode( $doc, 'ColorPool' );
	if ( ! $ColorPool ) {
		# Node hasn't been added yet, so add it.
		$ColorPool = $ResourcePool->appendChild( $doc->createElement( 'ColorPool' ) );
		$ColorPool->setAttribute('Class','Parameter');
		$ColorPool->setAttribute('Status','Available');
		$ColorPool->setAttribute('ID','CP' );
	} # end if
	
	my %colors;
	my $colors = $ColorPool->getElementsByTagName('Color');
#$openprint::log->debug("Colours: " . $colors->getLength() );

	for ( my $i = 0; $i < $colors->getLength() ; $i += 1 ) {
#$openprint::log->debug("Adding color : " . $colors->item($i)->getAttribute('Name') );
		$colors{$colors->item($i)->getAttribute('Name')} = 1;
	} # end foreach
	
	foreach my $color ( @side_one_colours, @side_two_colours ) {
		if ( ! $colors{$color} ) {
			my $Color = $ColorPool->appendChild( $doc->createElement( 'Color' ) );
			$Color->setAttribute('Name',$color);
			if ( $color eq 'Black' ) {
				$Color->setAttribute('CMYK','0 0 0 1');
			} elsif ( $color eq 'Cyan' ) {
				$Color->setAttribute('CMYK','1 0 0 0');
			} elsif ( $color eq 'Magenta' ) {
				$Color->setAttribute('CMYK','0 1 0 0');
			} elsif ( $color eq 'Yellow' ) {
				$Color->setAttribute('CMYK','0 0 1 0');
			} # end if
			$colors{$color} = 1;
		} # end if
	} # end foreach
	my $ColorantControlLink = $ResourceLinkPool->appendChild( $doc->createElement('ColorantControlLink'));
	$ColorantControlLink->setAttribute('Usage','Input' );
	$ColorantControlLink->setAttribute('rRef','CC'.$$sig_specs{'SignatureIndex'} );
	return $ColorantControl;

} # end sub JDF_ColorantControl
sub JDF_Device {
    my ( $doc, $Equipment, $version, $ResourcePool, $ResourceLinkPool ) = @_;

	my $Device = openprint::JDF::getNode( $ResourcePool, 'Device','DeviceID'=>$Equipment->jdf_id() );
	if ( ! $Device ) {
		$Device = $ResourcePool->appendChild( $doc->createElement('Device') );
		$Device->setAttribute('Class','Implementation' );
		$Device->setAttribute('DescriptiveName',$Equipment->jdf_name() );
		$Device->setAttribute('FriendlyName',$Equipment->jdf_name() );
		$Device->setAttribute('DeviceID', $Equipment->jdf_id() );
		$Device->setAttribute('ID', 'E'.$Equipment->id() );
		#$Device->setAttribute('Locked', 'false' );
		$Device->setAttribute('Status', 'Available' );
	} # end if
	my $DeviceLink = $ResourceLinkPool->appendChild( $doc->createElement('DeviceLink'));
	$DeviceLink->setAttribute('Usage','Input' );
	$DeviceLink->setAttribute('rRef','E'.$Equipment->id() );

	return $Device;
} # end sub JDF_Equipment

sub JDF_PaperIntent {
    my ( $doc, $sig_specs, $Paper, $version, $ResourcePool, $ResourceLinkPool ) = @_;

	my $PaperIntent = openprint::JDF::getNode( $doc, 'Media','MediaType'=>'Paper' );
	if ( ! $PaperIntent ) {
		$PaperIntent = $ResourcePool->appendChild( $doc->createElement('Media'));
#$PaperIntent = $TopResourcePool->appendChild( $Paper->JDF_Media( $doc ) );
		$PaperIntent->setAttribute('Class','Consumable');
		$PaperIntent->setAttribute('MediaType','Paper');
		$PaperIntent->setAttribute('PartUsage','Implicit');
		$PaperIntent->setAttribute('Status','Available');
		$PaperIntent->setAttribute('ID','Paper');
		$PaperIntent->setAttribute('PartIDKeys','SignatureName SheetName');
	} # end if
	my $SignaturePaperIntent = $PaperIntent->appendChild( $doc->createElement('Media') );
	$SignaturePaperIntent->setAttribute('SignatureName', 'Sig#'.$$sig_specs{'SignatureIndex'} );
	my $SheetPaperIntent = $SignaturePaperIntent->appendChild( $Paper->JDF_Media( $doc ) );
	$SheetPaperIntent->setAttribute('SheetName',sprintf('Sig#%dSheet#%d', $$sig_specs{'SignatureIndex'}, 1 ) );

	my $MediaLink = $ResourceLinkPool->appendChild( $doc->createElement('MediaLink'));
	$MediaLink->setAttribute('Usage','Input' );
	$MediaLink->setAttribute('rRef','Paper' );
	my $Part = $MediaLink->appendChild( $doc->createElement('Part'));
	$Part->setAttribute('SignatureName','Sig#'.$$sig_specs{'SignatureIndex'} );
	$Part->setAttribute('SheetName',sprintf('Sig#%dSheet#%d', $$sig_specs{'SignatureIndex'}, 1 ) );
	return $PaperIntent;

} # end sub JDF_PaperIntent

# Generates JDF for a signature...
sub JDF_PrintingProcess {

	my ( $doc, $Project, $sig_id, $sig_specs, $version ) = @_;
	$openprint::log->debug("Start JDF_PrintingProcess");

	my $services = $Project->services();
	my $printing_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] );
	my $Paper = openprint::Paper::load_from_signature( $Project, $sig_specs );


	my $TopResourcePool = openprint::JDF::getNode( $doc, 'ResourcePool' );

	my $project = $doc->createElement('JDF');
	$project->setAttribute('Status','Waiting');
	$project->setAttribute('Activation','Active');
# Printing Part # is project + sig, cuz a docket can have multiple projects, and we are talking about printing a sig
# This is so that the JMF handler can reference back to the service
	$project->setAttribute('JobPartID',$Project->id() . '#' . $sig_id );
	$project->setAttribute('Type', 'ConventionalPrinting' );
	$project->setAttribute('ID', 'CP'.$sig_id );
	my $summary = openprint::service::summary( $Project->id(), $sig_id );
	$project->setAttribute('DescriptiveName', $summary );
	my $ResourcePool = $project->appendChild( $doc->createElement('ResourcePool') );
	my $ResourceLinkPool = $project->appendChild( $doc->createElement('ResourceLinkPool') );

	my $NodeInfo = JDF_NodeInfo( $doc, $Project, $sig_id, $sig_specs, $version, $project, $ResourcePool, $ResourceLinkPool );
	my $JMF = $NodeInfo->appendChild( JMF::JMFNode($doc));
	my $QueryStatusChannel = $JMF->appendChild( JMF::QuerySetupPersistentChannel($doc, 'Status', {'ID'=>$sig_id} ) );
	$QueryStatusChannel = $JMF->appendChild( JMF::QuerySetupPersistentChannel($doc, 'Notification', {'ID'=>$sig_id} ) );

#my $NodeInfo = $ProductResourcePool->appendChild( $doc->createElement('NodeInfo') );
#my $JMF = $NodeInfo->appendChild( JMF::QuerySetupPersistentChannel( $doc ) );
#
#
# Dont' forget the wasts, tec

	my $Component = JDF_Component( $doc, $Project, $sig_id, $sig_specs, $version, $TopResourcePool, $ResourceLinkPool );
	my $PrintingParam = JDF_ConventionalPrintingParams( $doc, $Project, $sig_id, $sig_specs, $version, $ResourcePool, $ResourceLinkPool );

	if ( $Paper ) {
# Paper
		JDF_PaperIntent( $doc, $sig_specs, $Paper, $version, $TopResourcePool, $ResourceLinkPool );
	} # end if

	my $PlateIntent = JDF_PlateIntent( $doc, $Project, $sig_id, $sig_specs, $version, $TopResourcePool, $ResourceLinkPool );
	my $ExposedMedia = JDF_ExposedMedia( $doc, $Project, $sig_id, $sig_specs, $version, $TopResourcePool, $ResourceLinkPool );

# Add Press?
	my $Equipment;
	if ( $$sig_specs{'UsePress'} ) {
		my @Equipment = openprint::Equipment->find('strid'=>$$sig_specs{'UsePress'});
		$Equipment = shift @Equipment if @Equipment;
	} else {
		my @Equipment = openprint::Equipment->find('strid'=>$$sig_specs{'ddmPress'.$Project->ordered_quantity_index()} );
		$Equipment = shift @Equipment if @Equipment;
	} # end if
	if ( $Equipment ) {
		my $Device = JDF_Device( $doc, $Equipment, $version, $TopResourcePool, $ResourceLinkPool );
	} # end if

	my $ColorantControl = JDF_ColorantControl( $doc, $Project, $sig_id, $sig_specs, $version, $TopResourcePool, $ResourceLinkPool );

# Ink
	my $InkLink = $ResourceLinkPool->appendChild( $doc->createElement('InkLink'));
	$InkLink->setAttribute('Usage','Input' );
	$InkLink->setAttribute('rRef','INK');
	my $Part = $InkLink->appendChild( $doc->createElement('Part'));
	$Part->setAttribute('SheetName',sprintf('Sig#%dSheet#%d', $$sig_specs{'SignatureIndex'}, 1 ) );
	$Part->setAttribute('SignatureName','Sig#'.$$sig_specs{'SignatureIndex'});

	$openprint::log->debug("Leave JDF_PrintingProcess");
	return $project;

} # end sub JDF_PrintingProcess

1;
__END__
