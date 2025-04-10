use strict;
package openprint::Project;
require openprint::Object;
our @ISA = qw(openprint::Object);

use openprint ();

use vars qw( $log $dbh %config $debug $table $serial %fields %find_fields %transforms %defaults );
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*config = \%openprint::config;

require openprint::ProjectType;
require openprint::Company;
require openprint::Order;

require sql;
require openprint::OrderedProduct;
require openprint::OrderedProject;
require openprint::Project_Service;
require openprint::Todo;
require openprint::Bug;
require openprint::service;
require openprint::Project_Log;
require openprint::Estimating::Printing;

$debug = 1;

$table = 'tbl_projects';
$serial = 'lngProjectIndex_seq';

%fields = (
	id							=>	'lngprojectindex',
  #docket					=>	'lngdocketnumber',
	company_id			=>	'lngcustomerid',
	user_id					=>	'lnguserindex',
	reference				=>	'strprojectreference',
	comments				=>	'strcomments',
	design					=>	'strdesign',
	created_on			=>	'dtmcreationdate',
	updated_on			=>	'dtmlastmodified',
  #calculated_on		=>	'calculated_on',
	quantity1				=>	'intquantity1',
	quantity2				=>	'intquantity2',
	quantity3				=>	'intquantity3',
	status					=>	'strstatus',
  #mode						=>	'strmode',
	programs				=>	'strprograms',
	other_programs	=>	'strotherprograms',
	currency_id			=>	'currency_id',
	type_id					=>	'lngprojecttype',
	price1					=>	'price1',
	price2					=>	'price2',
	price3					=>	'price3',
	order_id				=>	'order_id',
	due_date				=>	'due_date',
  #externalrefnumber=>	'externalrefnumber',
  #reprint					=>	'reprint',
  #reprint_reason	=>	'reprint_reason',
  #reprint_description	=>	'reprint_description',
  #predefined			=>	'predefined',
  #rush							=>	'rush',
  #style_id					=>	'style_id',
	summary						=>	'summary',
  #markup						=>	'markup',
  #discount					=>	'discount',
  #credit_card_fee   =>  'credit_card_fee',
  #csr_commission    =>  'csr_commission',
  #priority					=>	'priority',
  #production_comments	=>	'production_comments',
ordered_quantity	=> undef,
ordered_quantity_index	=> undef,
ordered_price	=> undef,
);
%transforms = (
	id								=>	[ 's/\D//g', '<2147483647' ],
	markup						=>	[ 's/[^\-\d\.]//g' ],
	price1					=>	[ 's/[^\-\d\.]//g', '<2147483647' ],
	price2					=>	[ 's/[^\-\d\.]//g', '<2147483647' ],
	price3					=>	[ 's/[^\-\d\.]//g', '<2147483647' ],
	quantity1					=>	[ 's/\D//g' ],
	quantity2					=>	[ 's/\D//g' ],
	quantity3					=>	[ 's/\D//g' ],
	reference					=>	[ 's/\r\n/<br\/>/mg', 's/\n\r/<br\/>/mg', 's/\n/<br\/>/mg', 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g', 's/[^[:ascii:]]//g' ],
	comments					=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g', 's/[^[:ascii:]]//g' ],
	discount					=>	[ 's/[^\-\d\.]//g' ],
	csr_commission		=>	[ 's/[^\-\d\.]//g' ],
	credit_card_fee		=>	[ 's/[^\-\d\.]//g' ],
);
%defaults = (
	created_on	=>	q`'NOW()'`,
	updated_on	=>	q`'NOW()'`,
	calculated_on	=>	undef,
	docket		=>	undef,
	quantity1	=>	undef,
	quantity2	=>	undef,
	quantity3	=>	undef,
	price1		=>	undef,
	price2		=>	undef,
	price3		=>	undef,
	order_id	=>	undef,
	due_date	=>	undef,
	markup		=>	undef,
	priority	=>	undef,
	reprint		=>	0,
	reprint_description	=>	q`''`,
	discount				=>	undef,
	csr_commission	=>	undef,
	credit_card_fee	=>	undef,
);

%find_fields = (
	take_over		=> q{(SELECT MIN(starttime) FROM tbl_Project_Contents WHERE lngProjectIndex=id)},
	ordered_on		=>	q{(SELECT created_on FROM Orders WHERE orders.id=order_id)},
	salesrep_id		=>	'(SELECT salesrep_id FROM Orders WHERE orders.id=order_id)',
	takenover_on	=>	'(SELECT MIN(dtmtimestamp) FROM Project_Log WHERE project_id='.$table.'.'.$fields{id}.' AND '.$fields{description}.' LIKE \'Taken Over by%\')',
	approved_on		=>	q{(SELECT MAX(dtmtimestamp) FROM Project_Log WHERE project_id=projects.id AND description IN ('Marked Approved','Marked Proofs QA Approved'))},
	csr_id			=>	'(SELECT salesrep_id FROM Companies WHERE companies.id=company_id)',
	value			=>	[ 'price1', 'price2', 'price3' ],
	used_press_name	=>	q`(SELECT strValue FROM tbl_Service_Specifications WHERE lngProjectIndex=projects.id AND strName='UsePress')`,
	estimated_press_name	=>	q`(SELECT strValue FROM tbl_Service_Specifications WHERE lngProjectIndex=projects.id AND strName IN ('ddmPress1','ddmPress2','ddmPress3'))`,
	operator_id		=>	q`(SELECT user_id FROM Project_Service_Operators WHERE service_id IN (SELECT lngServiceIndex FROM tbl_Project_Contents WHERE lngprojectindex=projects.id))`,
	quote_id		=>	q`(SELECT quote_id FROM tbl_quote_details WHERE project_id=Projects.id)`,
	servicetype_id	=>	'(SELECT servicetype_id FROM tbl_project_contents WHERE lngprojectIndex=id)',
	type	=>	'(SELECT name FROM project_types WHERE project_types.id=type_id)',
);

sub delete {
	my $self = shift;
	if ( !$self->save({ status=>'Deleted' }) ) {
		$self->add_to_log( @openprint::session{'company_id','user_id'}, 'Deleted' );
	}
} # end sub delete

sub deleted {
	return $_[0]{status} eq 'Deleted' ? 1 : 0;
} # end sub deleted

sub undelete {
	$_[0]{status} = 'uncalculated';
	$_[0]->update_status();
	return '';
} # end sub undelete

sub destroy {
	my $self = shift;
	my $ac = sql::start_transaction( $openprint::dbh );
	foreach my $Product ( openprint::OrderedProduct->find( project_id=>$$self{id} ) ) {
		$Product->save({project_id=>undef});
	} # end foreach Product
	foreach my $Todo ( openprint::Todo->find( project_id=>$$self{id} ) ) {
		$Todo->save({project_id=>undef});
	} # end foreach Todo
	foreach my $B ( openprint::Bug->find( project_id=>$$self{id} ) ) {
		$B->destroy();
	} # end foreach bug
	sql::execute( $openprint::log, $openprint::dbh, q{DELETE FROM tbl_Service_Specifications WHERE lngProjectIndex=?}, $$self{id} );
	sql::execute( $openprint::log, $openprint::dbh, q{DELETE FROM tbl_Project_Contents WHERE lngProjectIndex=?}, $$self{id} );
	sql::execute( $openprint::log, $openprint::dbh, q{DELETE FROM Project_Log WHERE project_id=?}, $$self{id} );
	sql::execute( $openprint::log, $openprint::dbh, q{DELETE FROM Barcode_Log WHERE project_id=?}, $$self{id} );
	sql::execute( $openprint::log, $openprint::dbh, q{DELETE FROM Schedule WHERE projectindex=?}, $$self{id} );
	sql::execute( $openprint::log, $openprint::dbh, q{DELETE FROM paper_allocations WHERE project_id=?}, $$self{id} );
	sql::execute( $openprint::log, $openprint::dbh, q{DELETE FROM Project_files WHERE project_id=?}, $$self{id} );
	sql::execute( $openprint::log, $openprint::dbh, q{DELETE FROM Order_Contents WHERE lngprojectindex=?}, $$self{id} );
	foreach my $quote_id ( sql::execute( undef, undef, q{SELECT quote_id FROM tbl_Quote_Details WHERE project_id=?}, $$self{id} ) ) {
		my $Quote = new openprint::Quote( $quote_id );
		$Quote->add_log('Deleted Project ' . $$self{id} );
	} # end foreach
	sql::execute( $openprint::log, $openprint::dbh, q{DELETE FROM PressActivities WHERE project_id=?}, $$self{id} );
	sql::execute( $openprint::log, $openprint::dbh, q{DELETE FROM productionfeedback WHERE project_id=?}, $$self{id} );
	sql::execute( $openprint::log, $openprint::dbh, q{DELETE FROM signaturecapture WHERE project_id=?}, $$self{id} );
	sql::execute( $openprint::log, $openprint::dbh, q{DELETE FROM projects WHERE id=?}, $$self{id} );
	sql::end_transaction( $openprint::dbh, $ac );
} # end sub destroy

sub Type {
	if ( @_ > 1 ) {
		$_[0]{type_id} = $_[1]->id();	
	} # end nif
	return new openprint::ProjectType( $_[0]{type_id} );
} # end sub Type

sub type {
	return new openprint::ProjectType( $_[0]{type_id} )->name();
} # end sub type

sub get_project_type_service_index {
	my ( $self ) = @_;
	my $services = $self->services();

	if ( $$services{''} ) {
		return $$services{''}[0];
	} # end if
	return;
} # end sub

sub JDF_ProductIntent {
require openprint::JDF;
	my ( $self ) = @_;

	my $services = $self->services();
	my $printing_specs = openprint::service::get_specs_ref( $self, $$services{''}[0] );
	
	my $doc = new XML::DOM::Document;
	$doc->setXMLDecl( $doc->createXMLDecl( '1.0' ) );
	foreach my $sig_id ( $self->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $self, $sig_id );
		$doc->appendChild( openprint::JDF::PrintingProcess( $doc, $self, $sig_id, $sig_specs ) );
	} # end foreach
	return $doc;
} # end sub JDF_ProductIntent

sub jdf {
require openprint::JDF;
	my ( $self, $version ) = @_;
	$version = 1.3 if ! $version;
	my $ppi = 1;

	my $services = $self->services();
	my $printing_specs = openprint::service::get_specs_ref( $self, $$services{''}[0] );
	
	my $doc = new XML::DOM::Document;
	$doc->setXMLDecl( $doc->createXMLDecl( '1.0' ) );
	my $Product = $doc->appendChild($doc->createElement('JDF'));
	$Product->setAttribute('xmlns','http://www.CIP4.org/JDFSchema_1_1');
	$Product->setAttribute('xmlns:xsi','http://www.w3.org/2001/XMLSchema-instance');
	$Product->setAttribute('xsi:type','Product');
	$Product->setAttribute('Status','Waiting');
	$Product->setAttribute('Version', $version );
	$Product->setAttribute('MaxVersion', $version );
	$Product->setAttribute('JobID',$self->docket());
	$Product->setAttribute('JobPartID',$self->id());
	$Product->setAttribute('Type', 'Product' );
	$Product->setAttribute('ID', 'Docket'.$self->docket() );
	$Product->setAttribute('DescriptiveName', $self->summary() );
	#my $FinalResourcePool = $project->appendChild( $doc->createElement('ResourcePool') );
	#my $FinalResourceLinkPool = $Product->appendChild( $doc->createElement('ResourceLinkPool') );

	#my $Product = $project->appendChild($doc->createElement('JDF'));
	#$Product->setAttribute('Status','Waiting');
	#$Product->setAttribute('ID', 'Product'.$self->id() );
	my $ProductResourcePool = $Product->appendChild( $doc->createElement('ResourcePool') );
	my $ProductResourceLinkPool = $Product->appendChild( $doc->createElement('ResourceLinkPool') );

	my $Component = $ProductResourcePool->appendChild( $doc->createElement('Component') );
	$Component->setAttribute('Class', 'Quantity');
	$Component->setAttribute('ComponentType', 'FinalProduct Sheet');
	$Component->setAttribute('DescriptiveName', $self->Type()->name() );
	$Component->setAttribute('ID', 'Product'.$self->id() );
	$Component->setAttribute('Status','Unavailable');
	$Component->setAttribute('isWaste','false');
	$Component->setAttribute('AmountRequired',$self->ordered_quantity());
	$Component->setAttribute('ResourceWeight', $self->finished_weight());
	## THese are crucial for Metrix
	#$Component->setAttribute('ProductType','Body');
	$Component->setAttribute('Dimensions',join(' ', 
				72*$$printing_specs{txtFinalWidth},
				72*$$printing_specs{txtFinalHeight}, 
				72*$self->calliper(),
				));

	# Later on, this is accessed the getNode, 1.3 does not list this node in it's examples. This makes no sense without signature data
	#my $Layout = $ProductResourcePool->appendChild( openprint::JDF::Layout( $doc, $self, undef, undef, undef, $version ) );
	
	#$Component->setAttribute('ReaderPageCount','2');

	my $ComponentLink = $ProductResourceLinkPool->appendChild( $doc->createElement('ComponentLink') );
	$ComponentLink->setAttribute('Usage','Output');
	$ComponentLink->setAttribute('rRef', 'Product'.$$self{id} );
	$ComponentLink->setAttribute('Amount', $self->ordered_quantity() );

#my $Ink = $doc->createElement( 'Ink' );
	my $Ink = $ProductResourcePool->appendChild( $doc->createElement( 'Ink' ));
	$Ink->setAttribute( 'Class','Consumable' );
	$Ink->setAttribute( 'DescriptiveName','Printing Inks');
	$Ink->setAttribute( 'PartIDKeys','SignatureName SheetName Side Separation');
	$Ink->setAttribute( 'ID','INK' );
	$Ink->setAttribute( 'Status', 'Available' );

# Hack: Add a PlateMaker
	if ( 0 ) {
		my $Device = openprint::JDF::getNode( $doc, 'Device',DeviceID=>'PLA1001' );
		if ( ! $Device ) {
			$Device = $ProductResourcePool->appendChild( $doc->createElement('Device') );
			$Device->setAttribute('Class','Implementation' );
			$Device->setAttribute('DescriptiveName','Temporary Platemaker' );
			$Device->setAttribute('DeviceID', 'PLA1001' );
			$Device->setAttribute('ID', 'PLA1001' );
			$Device->setAttribute('Status', 'Available' );
		} # end if
	} # end if

# Each part of a project is a signature, and has it's own Product Node
	foreach my $sig_id ( $self->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $self, $sig_id );

		my $Component = $ProductResourcePool->appendChild( $doc->createElement('Component') );
		$Component->setAttribute('Class', 'Quantity');
		$Component->setAttribute('ComponentType', 'PartialProduct');
		$Component->setAttribute('DescriptiveName', $self->Type()->name() );
		$Component->setAttribute('ID', 'SUB'.$$sig_specs{SignatureIndex} );
		$Component->setAttribute('Status','Unavailable');
		$Component->setAttribute('ProductType', openprint::JDF::ProductType( $self, $sig_specs, $version ) );

		my $Pages = $$sig_specs{'PageQuantity'.$self->ordered_quantity_index()};
		$Pages = 2 if ! $Pages;
		$Component->setAttribute('ReaderPageCount',$Pages );
		my $SignatureIntent = openprint::JDF::JDF_SignatureIntent( $doc, $self, $sig_id, $sig_specs, $version );
		$Product->appendChild( $SignatureIntent );

# Add the printing Process for this sig
		$SignatureIntent->appendChild( openprint::JDF::JDF_PrintingGreyBox( $doc, $self, $sig_id, $sig_specs, $version ) );
		#$SignatureIntent->appendChild( openprint::JDF::JDF_PrintingProcess( $doc, $self, $sig_id, $sig_specs, $version ) );
		#openprint::JDF::JDF_PrintingProcess( $doc, $self, $sig_id, $sig_specs );
		my $SI_ResourceLinkPool = openprint::JDF::getNode( $SignatureIntent, 'ResourceLinkPool' );

		my $FinalInputComponentLink = $ProductResourceLinkPool->appendChild( $doc->createElement('ComponentLink') );
		$FinalInputComponentLink->setAttribute('Usage','Input');
		$FinalInputComponentLink->setAttribute('Amount',$self->ordered_quantity() );
		$FinalInputComponentLink->setAttribute('rRef','SUB'.$$sig_specs{SignatureIndex} );

		my @side_one_colours = openprint::Estimating::Printing::get_colours( $sig_specs,'SideOne' );
		my @side_two_colours = openprint::Estimating::Printing::get_colours( $sig_specs,'SideTwo' );
		my %SideColours = (
				Front=>\@side_one_colours,
				Back=>\@side_two_colours,
				);

		my $SigInk = $Ink->appendChild( $doc->createElement('Ink') );
		$SigInk->setAttribute('SignatureName','Sig#'.$$sig_specs{SignatureIndex});

		my $SigInkSheetName = $SigInk->appendChild( $doc->createElement('Ink') );
		$SigInkSheetName->setAttribute('SheetName','Sheet 1');

		foreach my $side ( 'Front','Back' ) {
			if ( @{$SideColours{$side}} ) {
				my $SigInkFront = $SigInkSheetName->appendChild( $doc->createElement('Ink') );
				$SigInkFront->setAttribute('Side',$side);
				foreach my $color ( @{$SideColours{$side}} ) {
					my $Separation = $SigInkFront->appendChild($doc->createElement('Ink'));
					$Separation->setAttribute('Separation',$color);
				} # end foreach
			} # end if
		} # end foreach Side
		#$SignatureIntent->appendChild( openprint::JDF::JDF_PrintingProcess( $doc, $self, $sig_id, $sig_specs ) );
		#$SignatureIntent->appendChild( openprint::JDF::JDF_ImpositionIntent( $doc, $self, $sig_id, $sig_specs ) );
		$SignatureIntent->appendChild( openprint::JDF::Prepress( $doc, $self, $sig_id, $sig_specs, $version ) );
		#my $ImpositionIntentLink = $SI_ResourceLinkPool->appendChild( $doc->createElement( 'ImpositionLink' ) );
		#$ImpositionIntentLink->setAttribute('Usage','Input');
		#$ImpositionIntentLink->setAttribute('rRef','Imposition'.$sig_id);
		
	} # end foreach Signature

	# Add Binding Info
	if ( my $binding = $self->get_book_type() ) {
		my $BindingIntent = $ProductResourcePool->appendChild( $doc->createElement('BindingIntent') );
		$BindingIntent->setAttribute('ID','BI'.$self->id() ); # FInal Binding
		$BindingIntent->setAttribute('Class','Intent' );
		$BindingIntent->setAttribute('Status','Available' );
		my $BindingType = $BindingIntent->appendChild( $doc->createElement('BindingType') );
		$BindingType->setAttribute('DataType','EnumerationSpan');
		$BindingType->setAttribute('Actual',$openprint::JDF::bindingtypes{$binding});
		$BindingType->setAttribute('Preferred',$openprint::JDF::bindingtypes{$binding});

		my $BindingIntentLink = $ProductResourceLinkPool->appendChild( $doc->createElement('BindingIntentLink') );
		$BindingIntentLink->setAttribute('Usage','Input');
		$BindingIntentLink->setAttribute('rRef','BI'.$self->id());
	} # end if


if ( 1 ) {
	require XML::DOM;
	require JMF;
	# THis is where we stick JMF Subscriptions
	#my $NodeInfo = $ProductResourcePool->appendChild( $doc->createElement('NodeInfo') );
	#$NodeInfo->setAttribute('ID','NI'.$self->id());
	#$NodeInfo->setAttribute('Class','Parameter');
	##$NodeInfo->setAttribute('Status','Available');
	#$NodeInfo->setAttribute('JobPriority','50');
	#my $JMF = $NodeInfo->appendChild( JMF::QuerySetupPersistentChannel( $doc ) );
	#my $NodeInfoLink = $ProductResourceLinkPool->appendChild( $doc->createElement('NodeInfoLink') );
	#$NodeInfoLink->setAttribute('rRef','NI'.$self->id());
	#$NodeInfoLink->setAttribute('Usage','Input');

	#my $JMF = $NodeInfo->appendChild( JMF::JMFNode($doc));
	#my $QueryStatusChannel = $JMF->appendChild( JMF::QuerySetupPersistentChannel($doc, 'Status') );
	#my $QueryStatusChannel = $JMF->appendChild( JMF::QuerySetupPersistentChannel($doc, 'Notification') );

	# Add Company Information
	#my $ResourcePool = $project->appendChild( $doc->createElement('ResourcePool') );
	my $CustomerInfo;
	if ( $version == 1.3 ) {
		$CustomerInfo = $ProductResourcePool->appendChild( $doc->createElement('CustomerInfo') );
		$CustomerInfo->setAttribute('ID', 'CustInfo' );
		my $CustomerInfoLink = $ProductResourceLinkPool->appendChild( $doc->createElement('CustomerInfoLink') );
		$CustomerInfoLink->setAttribute('Usage','Input');
		$CustomerInfoLink->setAttribute('rRef','CustInfo');
	} else {
		$CustomerInfo = $Product->appendChild( $doc->createElement('CustomerInfo') );
	} # end if
	$CustomerInfo->setAttribute('CustomerID',$self->Company->id() );
	#$CustomerInfo->setAttribute('Class', 'Parameter' );
	#$CustomerInfo->setAttribute('Status', 'Available' );
	#$CustomerInfo->setAttribute('DescriptiveName', $self->Company->name() );
	$CustomerInfo->setAttribute('CustomerJobName', $self->reference() );


	my $Contact = $CustomerInfo->appendChild( $doc->createElement('Contact') );
	$Contact->setAttribute('ContactTypes', 'Customer' );
	my $Person = $Contact->appendChild( $doc->createElement('Person') );
	$Person->setAttribute('FamilyName', $self->Order()->lastname() );
	$Person->setAttribute('FirstName', $self->Order()->firstname() );
	if ( $self->Order()->email() ) {
		my $ComChannel = $Person->appendChild( $doc->createElement('ComChannel') );
		$ComChannel->setAttribute('ChannelType','Email');
		$ComChannel->setAttribute('Locator',$self->Order()->email());
	} # end if
	if ( $self->Order()->phone() ) {
		my $ComChannel = $Person->appendChild( $doc->createElement('ComChannel') );
		$ComChannel->setAttribute('ChannelType','Phone');
		$ComChannel->setAttribute('Locator',$self->Order()->phone());
	} # end if
	if ( $self->Order()->fax() ) {
		my $ComChannel = $Person->appendChild( $doc->createElement('ComChannel') );
		$ComChannel->setAttribute('ChannelType','Fax');
		$ComChannel->setAttribute('Locator',$self->Order()->fax());
	} # end if
} # end if

	my $AuditPool = $Product->appendChild( $doc->createElement('AuditPool') );
	my $Created = $AuditPool->appendChild( $doc->createElement('Created') );
	$Created->setAttribute('Author', 'IntelligentQuote' );
	my @gmtime = gmtime(time);
	$Created->setAttribute('TimeStamp', sprintf('%.4d-%.2d-%.2dT%.2d:%.2d:%.2dZ', $gmtime[5]+1900, $gmtime[4]+1, $gmtime[3]+1,$gmtime[2],$gmtime[1],$gmtime[0] ) );

	return $doc;
} # end sub xml

sub get_quantities {
	my $self = shift;
	my ( $caller, undef, $line ) = caller;
$openprint::log->error("DEPRECATED call to get_quantities from $caller:$line");
	return @$self{'quantity1','quantity2','quantity3'};
} # end sub get_quantities

sub is_printed {
	my $self = shift;
	
	my %statuses = sql::execute( undef, undef, q{SELECT lngServiceIndex, strStatus FROM tbl_Project_Contents WHERE lngProjectIndex=?}, $$self{id} );
	foreach ( $self->signatures() ) {
		return 0 if sets::isin( $statuses{$_}, ['Ordered','In Production','uncalculated'] );
	} # end foreach
	return 1;
} # end sub is_printed

# This is sortof a state engine.	This function should update a project's status to whatever it should be.
sub update_status {
	my ( $self ) = @_;

	# The Pending Deposit to In Prepress trnasition is a manual one.
	return if $$self{status} eq 'Pending Deposit';
	return if $$self{status} eq 'Deleted';

	my %services = $self->get_services();
	my %service_statuses = sql::execute( $openprint::log, $openprint::dbh, q{SELECT lngServiceIndex, strStatus FROM tbl_Project_Contents WHERE lngProjectIndex=?}, $$self{id} );
	my %statuses = map { $_ => $_ } values %service_statuses;
	my $new_status = $$self{status};

	my $Order = new openprint::Order( $$self{order_id} );
	if ( $$self{order_id} and $Order->status() ne 'Incomplete' ) {

# This fixes the damage caused by re-opening an order
		foreach my $service_id ( keys %service_statuses ) {
			my $Service = $self->Service( $service_id );	
$openprint::log->debug("Service : " . $Service->service_type() . ' ' . $Service->status() );
			if ( $service_statuses{$service_id} eq 'calculated' ) {
				if ( $Service->status(undef) ne 'calculated' ) {
					$Service->save();
					$service_statuses{$service_id} = $Service->status();
				}
			} elsif ( $service_statuses{$service_id} eq 'Ordered' ) {
				if ( $Service->status(undef) ne 'Ordered' ) {
					$Service->save();
					$service_statuses{$service_id} = $Service->status();
				}
			}
		}
		%statuses = map { $_ => $_ } values %service_statuses;

# We now know that it has been ordered.

		if ( $statuses{'Waiting For Customer Approval'} ) {
			if ( $$self{status} ne 'Waiting For Customer Approval' ) {
				$self->add_to_log( @openprint::session{'company_id','user_id'}, "Marked Waiting For Customer Approval from $$self{status}" );
				$$self{status} = 'Waiting For Customer Approval';
				$self->save();
			} # end if
			return $$self{status};
		} elsif ( $statuses{'Waiting For QA Approval'} ) {
			if ( $$self{status} ne 'Waiting For QA Approval' ) {
				$self->add_to_log( @openprint::session{'company_id','user_id'}, "Marked Waiting For QA Approval from $$self{status}" );
				$$self{status} = 'Waiting For QA Approval';
				$self->save();
			} # end if
			return $$self{status};
		} elsif ( $statuses{'Proofs Out'} and ( $$self{status} ne 'Proofs Out' ) ) {
			$self->add_to_log( @openprint::session{'company_id','user_id'}, "Marked Proofs Out from $$self{status}" );
			$$self{status} = 'Proofs Out';
			$self->save();
			return $$self{status};
		} # end if

# At this point, we know that the project is ordered
		if ( $statuses{Ordered} ) {
			if ( $statuses{Approved} ) {
				if ( $self->is_printed() ) {
					$new_status = 'Printed';
				} else {
					$new_status = 'Approved';
				} # end if
			} else {
				if ( $self->is_printed() ) {
					$new_status = 'Printed';
					my $changed = 0;

					if ( $$self{status} eq 'In Prepress' ) {
# Check prepress services and mark complete
						my @prepress = openprint::print_project::get_services_in_category( $openprint::log, $openprint::dbh, $$self{id}, 'Prepress' );
						foreach my $s_id ( @prepress ) {
							if ( openprint::service::status( $$self{id}, $s_id ) ne 'Complete' ) {
								openprint::service::status( $$self{id}, $s_id, 'Complete' );
								$changed = 1;
							} # end if
						} # end foreach
						if ( $services{Proofs} ) {
							foreach my $s_id ( @{$services{Proofs}} ) {
								if ( openprint::service::status( $$self{id}, $s_id ) ne 'Approved' ) {
									openprint::service::status( $$self{id}, $s_id, 'Approved' );
									$changed = 1;
								} # end if
							} # end foreach
						} elsif ( $services{FilmStripping} ) {
							foreach my $s_id ( @{$services{FilmStripping}} ) {
								if ( openprint::service::status( $$self{id}, $s_id ) ne 'Approved' ) {
									openprint::service::status( $$self{id}, $s_id, 'Approved' );
									$changed = 1;
								} # end if
							} # end foreach

						} # end if
					} elsif ( $$self{status} eq 'Proofs Out' ) {
						if ( $services{Proofs} ) {
							foreach my $s_id ( @{$services{Proofs}} ) {
								if ( openprint::service::status( $$self{id}, $s_id ) ne 'Approved' ) {
									openprint::service::status( $$self{id}, $s_id, 'Approved' );
									$changed = 1;
								} # end if
							} # end foreach
						} # end if
					} elsif ( $$self{status} eq 'Approved' ) {
# normal
					} # end if
					if ( $services{NoBindery} ) {
						foreach my $s_id ( @{$services{NoBindery}} ) {
							if ( 'Complete' ne openprint::service::status( $$self{id}, $s_id ) ) {
								openprint::service::status( $$self{id}, $s_id, 'Complete' );
								$changed = 1;
							} # end if
						} # end foreach
					} # end if
					if ( $changed ) {
						return $self->update_status( );
					} # end if
				} else { # is printed
					$new_status = 'In Prepress';
				} # end if
			} # end if
		} else { # there isn't any ordered services
			if ( $services{CustomerPickUp} ) {
				if ( openprint::service::status( $$self{id}, $services{CustomerPickUp}[0] ) eq 'Complete' ) {
					$new_status = 'Picked Up';
				} # end if
			} elsif ( $self->shipping_type() eq 'CustomerPickup' ) {
				if ( $$self{status} ne 'Picked Up' ) {
					$new_status = 'Waiting For Pickup';
				} # end if
			} elsif ( $self->shipping_type() eq 'Delivery' ) {
				$new_status = 'Shipped';
			} else {
				if ( ! sets::isin( $$self{status}, [ 'Shipped', 'Picked Up' ] ) ) {
					$new_status = 'Complete';
				} # end if
			} # end if
		} # end if
	} else {
# Project is UnOrdered
		if ( $statuses{Ordered} ) {
			sql::update( $openprint::log, $openprint::dbh, 'tbl_Project_Contents', ['lngProjectIndex=? AND strStatus=?', $$self{id},'Ordered'], 'strStatus', 'calculated' );
			%service_statuses = sql::execute( $openprint::log, $openprint::dbh, q{SELECT lngServiceIndex, strStatus FROM tbl_Project_Contents WHERE lngProjectIndex=?}, $$self{id} );
			%statuses = map { $_ => $_ } values %service_statuses;
		} # end if
		if ( $self->Type()->type() eq 'MultiPage' ) {
require openprint::Estimating::MultiPage;
			foreach my $qty_index ( $self->quantity_indexes() ) {
				if ( openprint::Estimating::MultiPage::status( $$self{id}, undef, $qty_index ) ) {
					$new_status = 'uncalculated';
				} # end if
				my $ProjectService = $self->Service( $services{''}[0] );
				if ( openprint::Estimating::MultiPage::check( $self, $ProjectService, $qty_index ) ) {
					$ProjectService->status('uncalculated');
					$new_status = 'uncalculated';
				} # end if
			} # end foreach
		} # end if
		if ( $statuses{uncalculated} ) {
			$new_status = 'uncalculated';
		} elsif ( $statuses{calculated} ) { # This works because we have already checked for uncalculated
			$new_status = 'Unordered';
		} # end if
	} # end if

	if ( $$self{status} ne $new_status ) {
		$self->add_to_log( @openprint::session{'company_id','user_id'}, "Marked $new_status from $$self{status}" );
		$$self{status} = $new_status;
		$self->save();
	} # end if
	return $$self{status};

} # end sub update_project_status

sub save {
	my ( $self, $hash ) = @_;

	$self->set( $hash ? $hash : {} );
	$self->services(undef);
	foreach my $qty_index ( $self->quantity_indexes() ) {
		$self->price( $qty_index, undef );
	} # end foreach

	$$self{currency_id} = $openprint::session{Currency_id} if ! $$self{currency_id};
	$$self{company_id} = $openprint::session{company_id} if ! $$self{company_id};
	$$self{user_id} = $openprint::session{user_id} if ! $$self{user_id};
	$$self{status} = 'uncalculated' if ! $$self{status};
	$$self{predefined} = '0' if $$self{predefined} != 1;

	my $rc;
	if ( $$self{id} ) {
		$rc  = $self->SUPER::save($hash);
	} else {
		$rc  = $self->SUPER::save($hash);
		$openprint::Company->save({last_project_id=>$$self{id}}) if $openprint::Company and $openprint::Company->id() and $$self{id} and ! $rc;
	} # end if

	# I'm not sure we should be doing this.
	if ( (!$rc) and $$self{order_id} ) {
		my $OP = $self->Ordered_Project();
		if ( ! $$OP{order_id} ) {
			$log->error("Project $$self{id} has order_id $$self{order_id} but no OrderedProject");
		} else {
			$OP->save();
		} # end if
	} # end if
	return $rc;
} # eend sub save

sub quantity_indexes {
	my $self = shift;
	$$self{quantity_indexes} = shift if @_;
	if ( ! $$self{quantity_indexes} ) {
		$$self{quantity_indexes} = [];
		foreach my $qty_index ( 1 .. 3 ) {
			push @{$$self{quantity_indexes}}, $qty_index if $$self{"quantity$qty_index"};
		} # end foreach qty_index
	} # end if
	return @{$$self{quantity_indexes}};
} # end sub quantity_indexes

sub quantities {
	my $self = shift;
	return @$self{map { $$self{'quantity'.$_} ? 'quantity'.$_ : () } ( 1 .. 3 )};
} # end sub quantities

sub quantity {
	my ( $self, $index, $qty ) = @_;
	if ( $index eq 'Used' ) {
		return $self->ordered_quantity();
	} elsif ( defined $qty ) {
		$$self{"quantity$index"} = $qty;
		delete $$self{quantity_indexes};
	} # end if
	return $$self{'quantity'.$index};
} # end sub quantity

sub quantity1 {
	my $self = shift;
	if ( @_ ) {
		my $new_qty = shift;
		if ( $new_qty != $$self{quantity1} ) {
			$$self{quantity1} = $new_qty;
		} # end if
		delete $$self{quantity_indexes};
	} # end if
	return $$self{quantity1};
} # end sub quantity1

sub quantity2 {
	my $self = shift;
	if ( @_ ) {
		my $new_qty = shift;
		if ( $new_qty != $$self{quantity2} ) {
			$$self{quantity2} = $new_qty;
		} # end if
		delete $$self{quantity_indexes};
	} # end if
	return $$self{quantity2};
} # end sub quantity2

sub quantity3 {
	my $self = shift;
	if ( @_ ) {
		my $new_qty = shift;
		if ( $new_qty != $$self{quantity3} ) {
			$$self{quantity3} = $new_qty;
		} # end if
		delete $$self{quantity_indexes};
	} # end if
	return $$self{quantity3};
} # end sub quantity2

my @dont_copy = (
		'ServiceIndex','ProjectIndex','TemplateType',
		'txtEmployeeComments','rdbComplete','rdbApproved','rdbClientApproved', 'ddmApprovalDateMonth','ddmApprovalDateDay','ddmApprovalDateYear',
		'ddmCompletionDate.*','txtRunHours','txtDowntimeHours',
		'ddmPressCompletionDate.*', 'UsePress.*', 'rdbPressComplete.*',
		'UsedPaper.*',
		'txtMakeReadySetupHours', 'txtStartQuantity','txtFinalQuantity','txtWasteQuantity','txtEmployeeName',
		'.*Used',
		);

sub copy {
	my $self = shift;
	my $new = new openprint::Project();
	my @keys = keys %$self;
	@$new{@keys} = @$self{@keys};

	delete $$new{Services};
	$new->save({id=>undef, created_on=>undef,production_comments=>undef, order_id=>undef, docket=>undef} );

# Make this all one transaction... Don't need locking because a reload would get a different projectindex
	my $ac = sql::start_transaction( $openprint::dbh );
	my @contents = sql::execute( undef, undef, q{SELECT lngServiceIndex, servicetype_id, strStatus FROM tbl_Project_Contents WHERE lngProjectIndex=?}, $$self{id} );

	while ( @contents ) {
		my ( $service_index, $servicetype_id, $status ) = splice @contents, 0, 3;

# uncalc->uncalc,	*->calc
		if ( $status ne '' and sets::isin( $status, [ 'Pending Deposit', 'Ordered', 'Proofs Out', 'Approved', 'Complete' ] ) ) {
			$status = 'Unordered';
		} # end if

		my ( $new_service_index ) = sql::execute( undef, undef, q{SELECT nextval('ContentsServiceIndex_seq')} );
		sql::insert( undef, undef, 'tbl_Project_Contents',[
				lngProjectIndex	=>	$$new{id},
				lngServiceIndex	=>	$new_service_index,
				servicetype_id	=>	$servicetype_id,
				strStatus		=>	$status
				] );
		openprint::service::insert_service_spec( $openprint::log, $openprint::dbh, $new->id(), $new_service_index, 'ProjectIndex', $new->id(), 1 );
		openprint::service::insert_service_spec( $openprint::log, $openprint::dbh, $new->id(), $new_service_index, 'ServiceIndex', $new_service_index, 1 );

		my $specs = openprint::service::get_specs_ref( $self, $service_index );
		foreach my $key ( keys %$specs ) {
			if ( ! sets::isin_regx( $key, @dont_copy ) ) {
				openprint::service::insert_service_spec( $openprint::log, $openprint::dbh, $new->id(), $new_service_index, $key, $$specs{$key}, 1 );
			} # end if
		} # end foreach
	} # end while contents
	sql::end_transaction( $openprint::dbh, $ac );
	delete $$new{Services};

	return $new;
} # end sub copy

sub add_to_log {
	my ( $self, $cust_id, $user_id, $text ) = @_;
	my $Log = new openprint::Project_Log();
	$Log->save({ 
			project_id	=>	$$self{id},
			company_id	=>	$cust_id,
			user_id		=>	$user_id,
			description	=>	$text,
			});
} # end sub add_to_log

sub get_services {
	my $self = shift;
	if ( ! exists $$self{Services} ) {
		my %results;
		my @data = sql::execute( undef, undef, 'SELECT (SELECT '.$openprint::ServiceType::fields{name}.' FROM '.$openprint::ServiceType::table.' WHERE '.$openprint::ServiceType::fields{id}.'=servicetype_id), lngServiceIndex FROM tbl_Project_Contents WHERE lngProjectIndex=?', $$self{id} );
		while ( my ( $id, $index ) = splice @data, 0, 2 ) {
			push @{$results{$id}}, $index;
		} # end while
		$$self{Services} = \%results;
	} # end if
	return %{$$self{Services}};
} # end sub get_service_hash

sub servicetype_id {
	my ($self, $s_id) = @_;
	if (!exists $$self{service_types}) {
		%{$$self{service_types}} = sql::execute( undef, undef, q{SELECT lngserviceindex, servicetype_id FROM tbl_Project_Contents WHERE lngProjectIndex=?}, $$self{id} );
	} # end if
	if (!exists $$self{service_types}{$s_id}) {
    #my ( $caller, undef, $line ) = caller;
		#$openprint::log->error("Request for servicetype_id for $s_id, reloading from $caller:$line");
		Carp::cluck("No servicetype_id for $s_id Project::Service");
		%{$$self{service_types}} = sql::execute( undef, undef, q{SELECT lngserviceindex, servicetype_id FROM tbl_Project_Contents WHERE lngProjectIndex=?}, $$self{id} );
		if (!$$self{service_types}{$s_id}) {
			$openprint::log->error("Request for servicetype_id for $s_id, not found ");
		}
	} # end if
  if (!$$self{service_types}{$s_id}) {
		%{$$self{service_types}} = sql::execute( undef, undef, q{SELECT lngserviceindex, (SELECT lngindex from tbl_service_types where strid= strservicetype) FROM tbl_Project_Contents WHERE lngProjectIndex=?}, $$self{id} );
  }

	return $$self{service_types}{$s_id};
} # end sub servicetype_id

sub ServiceType {
  my ( $self, $s_id ) = @_;
  if (!$s_id) {
    $openprint::log->error("No s_id passed to ServiceType for project $$self{id}");
    return undef;
  }
	return new openprint::ServiceType( $self->servicetype_id( $s_id ) );
} # end sub ServiceType

sub has_service {
	my $self = shift;
  my $service = shift;

  my $services = $self->services();
  return $$services{$service} ? @{$$services{$service}} : () if wantarray;
  return $$services{$service} ? $$services{$service}[0] : undef;
}

sub services {
	my $self = $_[0];

	if ( @_ > 1 ) {
		delete $$self{Services};
	} # end if
	
	if ( $$self{id} and ! $$self{Services} ) {
		my %results;
		my @data = sql::execute( undef, undef, 'SELECT (SELECT '.$openprint::ServiceType::fields{name}.' FROM '.$openprint::ServiceType::table.' WHERE '.$openprint::ServiceType::fields{id}.'=servicetype_id), lngServiceIndex FROM tbl_Project_Contents WHERE lngProjectIndex=?', $$self{id} );
		while ( my ( $id, $index ) = splice @data, 0, 2 ) {
			$id = '' if ! $id;
			push @{$results{$id}}, $index;
		} # end while
		$$self{Services} = \%results;
	} # end if
	return $$self{Services};
} # end sub services

sub summary {
	my $self = shift;

	if ( @_ ) {
		$$self{summary} = shift;
	} # end if
	if ( ! $$self{summary} ) {
		my $summary = $self->Type()->description();

		my $services = $self->services();
		if ( $$services{''} and @{$$services{''}} ) {
			my $printing_specs = openprint::service::get_specs_ref( $self, $$services{''}[0] );
			if ( $$printing_specs{Versions} ) {
				$summary .= ' '.$$printing_specs{Versions}.' versions ';
			} # end if
			if ( $$printing_specs{PageQuantity} ) {
				$summary .= ' '.$$printing_specs{PageQuantity}.'pg ';
			} # end if

			if ( $self->Type()->name() eq 'PresentationFolders' ) {
				$summary .= ' '.$$printing_specs{rdbPanels} . ' Panel ' . $$printing_specs{PocketSize} . '&quot; ';
			} # end if

			if ( $$printing_specs{txtTotalPageQuantity} ) {
				$summary .= sprintf(' %s&quot;x%s&quot; ', 1*$$printing_specs{txtFinalWidth},1*$$printing_specs{txtFinalHeight});
				if ( $$printing_specs{rdbCover} eq 'Different' ) {
					my $cover_pages = 0;
					foreach my $ss_id ( $self->signatures({Group=>1}) ) {
						my $sig_specs = openprint::service::get_specs_ref( $self, $ss_id );
						$cover_pages += $$sig_specs{GroupPageQuantity};
						last;
					} # end foreach
					$summary .= sprintf('%dpg+Cover ', $$printing_specs{txtTotalPageQuantity} - $cover_pages );
				} else {
					$summary .= sprintf('%dpg ', $$printing_specs{txtTotalPageQuantity} );
					$summary .= $$printing_specs{rdbCover}.' Cover';
				} # end if
				if ( $$printing_specs{rdbTemplateType} eq 'Unbound' ) {
					$summary .= ' Unbound';
				} # end if

				$summary .= '<br/>';
			} # end if
			my @groups = sql::execute( undef, undef, 'SELECT DISTINCT strvalue FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND strName=?', $$self{id}, 'Group' );

# I believe the point of this is to stick the Printed Web or Sheetfed into the summary.	Nastily executed.
# The logic is, each group has to be either all sheetfed, or all web (or digital, etc).	
			foreach my $group_id ( sort @groups ) {
				my @sigs = $self->signatures({Group=>$group_id});
				if ( ! @sigs ) {
					$openprint::log->error( "No sigs for Group $group_id, but there pretty much to be since we have this group index.  Signatures must be out of date");
					$self->services(undef);
					@sigs = $self->signatures({Group=>$group_id});
					if ( ! @sigs ) {
						$openprint::log->error( "Still No sigs for Group $group_id, after reloading" );
						next;
					} # end if
				} # end if

				my $sig_specs = openprint::service::get_specs_ref( $self, $sigs[0] );
				my $group_html = openprint::Estimating::Printing::summary( $self, $sigs[0], $sig_specs );
				if ( $$printing_specs{"PrintingType-$group_id"} ) { 
					$group_html .= '<span class="Sheetfed">Printed '.$$printing_specs{"PrintingType-$group_id"}.'</span><br/>';
				} #endif Web
				$summary .= $group_html if $group_html;
			} # end foreach Group
		} # end if

		foreach my $Category ( openprint::ServiceType_Category->find(order=>'sorting') ) {
			next if sets::isin( $Category->name(), [ 'Printing','Coatings' ] );
			foreach my $ServiceType ( openprint::ServiceType->find(category_id=>$Category->id()) ) {
				next if ! $$services{$ServiceType->name()};
				next if ! $ServiceType->summary_visible();
				foreach my $service_id ( @{$$services{$ServiceType->name()}} ) {
					my $service_specs = openprint::service::get_specs_ref( $self, $service_id );
					my $project_summary = eval( 'openprint::Estimating::'.$ServiceType->type().'::project_summary( $self, $service_id, $service_specs );' );
					#$openprint::log->warn("Error eval $$ServiceType{type} ::project_summary() : $@") if $@;
					if ( $project_summary ) {
						$summary .= $project_summary;
					} else {
						$summary .= ' ' . $ServiceType->description();
						if ( $_ = eval( 'openprint::Estimating::'.$ServiceType->type().'::summary( $self, $service_id, $service_specs );' ) ) {
							if ( ref $_ eq 'ARRAY' ) {
							$summary .= ' :'.$$_[0] . '<br/> ';
							} else {
							$summary .= ' :'.$_ . '<br/> ';
							} # end if
						} else {
							$summary .= ',';
						} # end if
					} # end if
				} # end foreach service
			} # end foreach ServiceType
		} # end foreach category
		$summary =~ s/(.*),$/$1/m;
		$$self{summary} = $summary;
	} # end if
	
	return $$self{summary};
} # end sub summary

sub company {
	return new openprint::Company( $_[0]{company_id} );
} # end sub company
sub Company {
	return new openprint::Company( $_[0]{company_id} );
} # end sub company

sub requested_date {
	my $OP = $_[0]->Ordered_Project();
	if ( @_ > 1 ) {
		$$OP{requested_for} = $_[1];
	} # end if
	return $$OP{requested_for};
} # end sub requested_date
sub requested_for {
	my $OP = $_[0]->Ordered_Project();
	if ( @_ > 1 ) {
		$$OP{requested_for} = $_[1];
	} # end if
	return $$OP{requested_for};
} # end sub requested_for

sub shipping_type {
	my $OP = $_[0]->Ordered_Project();
	
	if ( @_ > 1 ) {
		$$OP{shipping_type} = $_[1];
	} # end if
	if ( ! $$OP{shipping_type} ) {
		my $services = $_[0]->services();
		$$OP{shipping_type} = join(',', map { $_->ServiceType()->name() } openprint::Project_Service->find(project_id=>$_[0]{id},category=>'Shipping') );
	} # end if
	return $$OP{shipping_type};
} # end sub shipping_type

sub ordered_quantity {
	my $qty_index = $_[0]->ordered_quantity_index();
	if ( $qty_index ) {
		return $_[0]{'quantity'.$qty_index};
	}

	return undef;
} # end sub ordered_quantity

sub ordered_quantity_index {
	my $OP = $_[0]->Ordered_Project();
	if ( @_ > 1 ) {
		$$OP{quantity_index} = $_[1];
	} # end if

	if ( $$OP{order_id} and ! $$OP{quantity_index} ) {
		my @qtys = $_[0]->quantity_indexes();
#$openprint::log->debug("Project ordered_qty_index (@qtys)");
# A This causes problems reporting ordered info on projects that havn't been ordered
# B putting it back but with an additional order_id check
		if ( 1 == @qtys ) {
			$$OP{quantity_index} = $qtys[0];
		} # end if
	} # end if
	return $$OP{quantity_index};
} # end sub ordered_quantity_index

sub ordered_price {
	my $OP = $_[0]->Ordered_Project();
	if ( ! $OP ) {
		$openprint::log->error('No OP in ordered_price');
	} else {
		return $$OP{price} if $$OP{price};
		return $_[0]{'price'.$$OP{quantity_index}} if $$OP{quantity_index};
	} # end if
	return 0;
} # end sub ordered_price

sub ordered_Price {
	my $price = $_[0]->ordered_price();
	return { Cost=>$price, currency_id=>$_[0]{currency_id}, Price=>$price };
} # end sub ordered_Price

sub prices {
	my $self = shift;
	return @$self{map { $$self{"quantity$_"} ? 'price'.$_ : () } ( 1 .. 3 ) };
}
sub price {
	my ( $self, $qty_index, $new ) = @_;
	if ( @_ == 3 ) {
		$$self{'price'.$qty_index} = $new;
	} # end if
	if ( ! defined $$self{'price'.$qty_index} ) {
		if ( $$self{id} ) {
			my $services = $self->services();
			foreach my $k ( keys %$services ) {
				foreach ( @{$$services{$k}} ) {
					my $specs = openprint::service::get_specs_ref( $self, $_ );
					$$self{'price'.$qty_index} += $$specs{'txtPrice'.$qty_index};
					#$openprint::log->debug("Getting " . $$specs{'txtPrice'.$qty_index} . " from $k $_");
				} # end foreach
			} # end foreach
		} # end if
	} # end if
#$openprint::log->debug("Price $qty_index " . $$self{'price'.$qty_index} );
	return $config{ProjectMoneyFormat} ? sprintf( $config{ProjectMoneyFormat}, $$self{'price'.$qty_index} ) : $$self{'price'.$qty_index};
} # end sub price
sub unit_price {
	my ( $self, $qty_index ) = @_;
#$openprint::log->debug("Unit Price: ".$$self{'price'.$qty_index}."/".$$self{'quantity'.$qty_index}." = " . $$self{'price'.$qty_index}/$$self{'quantity'.$qty_index} );
	return sprintf( $config{UnitPriceFormat}, $self->price($qty_index)/$$self{'quantity'.$qty_index} );
} # end sub unit_price
sub m_price {
	my ( $self, $qty_index ) = @_;
	my $m_price = 0;
	my $services = $self->services();
	foreach my $type ( keys %$services ) {
		foreach my $service_id ( @{$$services{$type}} ) {
			my $specs = openprint::service::get_specs_ref( $self, $service_id );
			$m_price += $$specs{'MPrice'.$qty_index};	
		} # end foreach service_id
	} # end foreach type
	return sprintf( $config{UnitPriceFormat}, $m_price );
} # end sub m_price


sub Price {
	my ( $self, $index ) = @_;
	return { Cost=>$$self{'price'.$index}, currency_id=>$$self{currency_id}, Price=>$$self{'price'.$index} };
} # end sub price

sub Order {
	return new openprint::Order( $_[0]{order_id} );
}

sub signatures {
	my ( $self, $params ) = @_;

	my $services = $self->services();

  # eprint support
  if ($$services{Printing}) {
    return @{$$services{Printing}};
  }

	if ( $params and $$services{Signature} ) {
		my @sigs;
		foreach my $s_id ( @{$$services{Signature}} ) {
			my $specs = openprint::service::get_specs_ref( $self, $s_id );

			if ( $$params{type} ) {
				next if $$specs{txtSignatureType} ne $$params{type};
			} # end if
			if ( exists $$params{Group} ) {
				next if $$specs{Group} != $$params{Group};
			} # end if
			push @sigs, $s_id;
		} # end foreach signatures
		if ( $$params{sort} ) {
            return sort {
                my $a_specs = openprint::service::get_specs_ref( $self, $a );
                my $b_specs = openprint::service::get_specs_ref( $self, $b );
                $$a_specs{Group} <=> $$b_specs{Group} || $$a_specs{SignatureIndex} <=> $$b_specs{SignatureIndex};
            } @sigs;
		} # end if
		return @sigs;
	} # end if
	return @{$$services{Signature}} if $$services{Signature} and @{$$services{Signature}};

	return;
} # end sub signatures

sub status_change {
	my ( $self, $company_id, $user_id, $new_status ) = @_;
	$company_id = $openprint::session{company_id} if ! $company_id;
	$user_id = $openprint::session{user_id} if ! $user_id;
require openprint::ScheduledJob;

	$self->add_to_log( $company_id,$user_id, 'Marked '.$new_status );
	if ( $new_status eq 'Printed' ) {
		foreach $_ ( $self->signatures() ) {
			openprint::service::status( $$self{id}, $_, 'Complete' );
		} # end foreach signature
		foreach my $Job ( openprint::ScheduledJob->find( project_id=>$$self{id}) ) {
			$Job->delete();
		} # end foreach
		if ( $$self{docket} ) {
			foreach my $PA ( openprint::PaperAllocation->find( docket=>$$self{docket}) ) {
				$PA->delete();
				$self->add_to_log( $company_id, $user_id, 'Freeing allocated paper: ' . $PA->quantity() . $PA->units() );
			} # end foreach AP
		} # end if
	} elsif ( sets::isin( $new_status, ['Bindery Complete' ] ) ) {
		foreach my $s_id ( $self->signatures() ) {
			openprint::service::status( $$self{id}, $s_id, 'Complete' );
		} # end foreach
		my $services = $self->services();
		openprint::service::status( $$self{id}, $$services{''}[0], 'Complete' ) if $$services{''};
		foreach my $s_id ( openprint::print_project::get_services_in_category( $openprint::log, $openprint::dbh, $$self{id}, 'Bindery' ) ) {
			openprint::service::status( $$self{id}, $s_id, 'Complete' );
		} # end foreach
		foreach my $Job ( openprint::ScheduledJob->find(project_id=>$$self{id}) ) {
			$Job->delete();
		} # end foreach
		$self->update_status();
		if ( $$self{docket} ) {
			foreach my $PA ( openprint::PaperAllocation->find( docket=>$$self{docket}) ) {
				$PA->delete();
			} # end foreach AP
		} # end if

	} elsif ( sets::isin( $new_status, ['Shipped','Picked Up', 'Complete'] ) ) {
		sql::update( undef, undef, 'tbl_Project_Contents', ["lngProjectIndex=? AND strStatus != ''", $$self{id}], 'strStatus', 'Complete' );
# Remove jobs from the Schedule when marked complete.
		foreach my $Job ( openprint::ScheduledJob->find( project_id=>$$self{id}) ) {
			$Job->delete();
		} # end foreach
		$self->status($new_status);
		if ( $$self{docket} ) {
			foreach my $PA ( openprint::PaperAllocation->find(docket=>$$self{docket}) ) {
				$PA->delete();
			} # end foreach AP
		} # end if
	} # end if
	$self->save();
	$self->Order()->update_status() if $self->order_id();
} # end sub status_change

sub User {
	return new openprint::User( $_[0]{user_id} );	
} # end sub User

# Was added when writing the PPF Monnitor, can be used to add a specific signature
# it uses add-service, which clears Services hash
sub add_signature {
	my ( $self, $sig_index, $status, $data ) = @_;
	
	$self->lock();
	my $print_service_index = $self->add_service('Signature', $data);
	if ( !$print_service_index ) {
		$log->error('Error adding Signature!');
		$self->unlock();
		return;
	} # end if
	openprint::service::status($self->id(), $print_service_index, $status) if $status;
	if ( !$sig_index ) {
		$_ = q{SELECT MAX(strValue::integer) FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND strName='SignatureIndex'};
		( $sig_index ) = sql::execute(undef, undef, $_, $self->id());
		$sig_index += 1;
	} # end if
	openprint::service::insert_service_spec( $log, $dbh, $self->id(), $print_service_index, 'SignatureIndex', $sig_index );
	delete $$self{calliper};
	$self->unlock();
	return $print_service_index;
} # end sub add_signature

sub copy_signature {
	my ( $self, $sig_specs, $data, $status ) = @_;
	$self->lock();
	my $new_service_index = $self->add_signature( undef, $status );
	if ( ! $new_service_index ) {
		$log->error('Error copying signature.');
		$self->unlock();
		return;
	} # end if
	my $new_specs = openprint::service::get_specs_ref( $self, $new_service_index );

	foreach my $key ( openprint::Estimating::Printing::variables( $$self{id}, $new_service_index, $new_specs, $sig_specs ) ) {
		next if $key eq 'SignatureIndex';
		if ( exists $$data{$key} ) {
			openprint::service::insert_service_spec( $log, $dbh, $self->id(), $new_service_index, $key, $$data{$key}, ! exists $$new_specs{$key} );
		} else {
			openprint::service::insert_service_spec( $log, $dbh, $self->id(), $new_service_index, $key, $$sig_specs{$key}, ! exists $$new_specs{$key} );
		} # end if
	} # end foreach
	$self->unlock();
	return $new_service_index;
} # end sub copy_signature

sub Template {
	return new openprint::QuoteLevel( $_[0]{style_id} );
} # end sub Template

sub get_due_date {
	my ( $self ) = @_;
	my $duedatedays = 0;
	foreach my $signature_service_index ( $self->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $self, $signature_service_index );
# Lookup how many days to add to due date
		if ( my @Equipment = openprint::Equipment->find( strid=>$$sig_specs{UsePress} ) ) {
			( $_ ) = $Equipment[0]->specification('DueDateDays');
			if ( $_ > $duedatedays ) {
				$duedatedays = int $_;
			} # end if
		} # end if
	} # end foreach signature_service_index

	if ( ! $duedatedays ) {
		$duedatedays = 5;
	} # end if

	my $runtime = 0;
	foreach ( $self->signatures() ) {
		$runtime += openprint::service::get_runtime( $self, $_ );
$openprint::log->debug("Adding runtime $runtime");
	} # end foreach
$openprint::log->debug('Adding runtime days: ' . int( $runtime / ( 24*60 ) ) );
	$duedatedays += int( $runtime / ( 24*60*60 ) );
	
	return sprintf('%.4d-%.2d-%.2d', misc::add_delta_business_days( Date::Calc::Today(), $duedatedays ) );
} # end sub get_due_date

sub Ordered_Product {
	my ( $self ) = @_;
	if ( ! exists($$self{Ordered_Product}) ) {
		my @Products = openprint::OrderedProduct->find( project_id=>$$self{id} );
		if ( @Products == 1 ) {
			$$self{Ordered_Product} = $Products[0];
		} elsif ( @Products ) {
			$log->error("More than 1 OrderedProduct returned in Project::OrderedProduct");
		} # end if
	} # end if
	return $$self{Ordered_Product};
} # end sub Ordered_Product

sub Ordered_Project {
	$_[0]{Ordered_Project} = $_[1] if @_ > 1;

	if ( ! exists $_[0]{Ordered_Project} ) {
		$_[0]{Ordered_Project} = openprint::OrderedProject->find_one(order_id=>$_[0]{order_id}, project_id=>$_[0]{id}) if $_[0]{order_id};
	} # end if

	if ( ! $_[0]{Ordered_Project} ) {
		$_[0]{Ordered_Project} = new openprint::OrderedProject();
		$_[0]{Ordered_Project}->project_id( $_[0]{id} );
	} # end if

	return $_[0]{Ordered_Project};
} # end sub Ordered_Project


# Let's talk LOCKING
# don't need to lock project_contents... cuz it's just an insert....
sub add_service {
	my ( $self, $type, $data, $options ) = @_;
  $data = {} if !$data;

	my $ServiceType;
	if ( ref $type ne 'openprint::ServiceType' ) {
		if ( ! ( $ServiceType = openprint::ServiceType->find_one( name=>$type ) ) ) {
			$log->warn("Service $type IS NOT in the system.");
			return;
		} # end if
	} else {
		$ServiceType = $type;
	} # end if

	$self->lock();

	my $Service = new openprint::Project_Service();
	$Service->save({
      project_id=>$$self{id},
      ( status=>$$options{status} ? $$options{status} : 'uncalculated' ),
      servicetype_id=>$ServiceType->id()
    });
	my $service_index = $$Service{service_id};
	$openprint::log->debug("Added Service $$ServiceType{name} at $service_index");
	$openprint::log->error("Adding Service $$ServiceType{name} at $service_index with no project type") if ! $$self{type_id};

	# Do this so that it doesn't try to load the specs, saving 1 db call.
	$openprint::service::specs_cache{$service_index} = {};
	openprint::service::insert_service_spec($log, $dbh, $$self{id}, $service_index, 'ServiceType', $ServiceType->name(), 1);
	my @Defaults = openprint::ServiceType_Default->find(
    'projecttype_id is null or =' => $$self{type_id},
    servicetype_id=>$ServiceType->id(),
    order=>'projecttype_id NULLS FIRST'
  );
	foreach my $n ( @Defaults ) {
    $openprint::log->debug('Setting initial default '.$n->to_string());
  }
	my %defaults = map { $_->name(), $_->value() } @Defaults;
	foreach my $n ( keys %defaults ) {
    $openprint::log->debug('Setting initial default '.$n.'=>'.$defaults{$n});
  }
	
	my $module = 'openprint::Estimating::'.$ServiceType->type();
	if ( my $function = $module->can('setup_defaults') ) {
		my %setup_defaults = $function->( $self );
    foreach my $n ( keys %setup_defaults ) {
      $openprint::log->debug('Setting initial setup default '.$n.'=>'.$setup_defaults{$n});
    }
    @defaults{keys %setup_defaults} = values %setup_defaults;
	} # end if

	foreach my $qty_index ( $self->quantity_indexes() ) {
    $defaults{'txtQuantity'.$qty_index} = $self->quantity($qty_index);
	} # end foreach

  @defaults{keys %{$data}} = values %{$data};
	foreach my $n ( keys %{$data} ) {
    $openprint::log->debug('Setting data default '.$n.'=>'.$$data{$n});
  }
	foreach my $n ( keys %defaults ) {
    $openprint::log->debug('Setting default '.$n.'=>'.$defaults{$n});
		openprint::service::insert_service_spec($log, $dbh, $$self{id}, $service_index, $n, $defaults{$n}, 1);
	} # end foreach default

	if ( ! $$self{Services}{$ServiceType->name()} ) {
		$$self{Services}{$ServiceType->name()} = [ $$Service{service_id} ];
	} else {
		push @{$$self{Services}{$ServiceType->name()}}, $$Service{service_id};
	}
	delete $$self{service_types};
	delete $$self{signatures};

  # FIXME Why are we saving here? prices would only change if there eas a default price
	foreach my $qty_index ( $self->quantity_indexes() ) {
		$self->price($qty_index,undef);
	} # end foreach
	$self->save();
	$self->unlock();
	return $service_index;
} # end sub add_service

sub started_on {
	my ( $self ) = @_;
	return sql::execute( undef, undef, q{ SELECT MIN(starttime) FROM tbl_Project_Contents WHERE lngProjectIndex=?}, $$self{id} );
} # end sub started_on

sub takeover_on {
	my ( $self ) = @_;
	if ( ! $$self{takeover_on} ) {
		@$self{takeover_on} = sql::execute( undef, undef, q`SELECT MIN(dtmtimestamp) FROM Project_Log WHERE project_id=? AND (description LIKE 'Assigning%' OR description LIKE 'Taken Over by%' OR description LIKE 'Marked Approved' OR description LIKE 'Marked Proofs Out%' OR description LIKE 'Added Proof%' OR description LIKE 'Additional Charges%')`, $$self{id} );
	} # end if
	return $$self{takeover_on};
} # end sub takeover_on

sub takeover_on_seconds {
	return Date::Parse::str2time( $_[0]->takeover_on() );
} # end sub takeover_on_seconds

sub prepress_start_on {
	my ( $self ) = @_;
	if ( ! $$self{prepress_start_on} ) {
	@$self{prepress_start_on} = sql::execute( undef, undef, q`SELECT MIN(dtmtimestamp) FROM Project_Log WHERE project_id=? AND ( description IN ('Marked In Prepress') OR description LIKE 'Add to Order%' )`, $$self{id} );
	} # end if
	return $$self{prepress_start_on};
} # end sub prepress_start_on

sub prepress_start_on_seconds {
	return Date::Parse::str2time( $_[0]->prepress_start_on() );
} # end sub prepress_start_on_seconds

sub ordered_on {
	my ( $self ) = @_;
	if ( ! exists $$self{ordered_on} ) {
		@$self{ordered_on} = sql::execute( undef, undef, q`SELECT MAX(dtmtimestamp) FROM Project_Log WHERE project_id=? AND description LIKE 'Add to Order%'`, $$self{id} );
		if ( ! $$self{ordered_on} ) {
			$$self{ordered_on} = $self->Order()->created_on();
		} # end if
	} # end if
	return $$self{ordered_on};
} # end sub ordered_on

sub ordered_on_seconds {
	return Date::Parse::str2time( $_[0]->ordered_on() );
} # end sub ordered_on_seconds

sub completed_on {
	my ( $self ) = @_;
	if ( ! exists $$self{completed_on} ) {
		@$self{completed_on} = sql::execute( undef, undef, q`SELECT MAX(dtmtimestamp) FROM Project_Log WHERE project_id=? AND description IN ('Marked Waiting For Pickup','Marked Shipped','Marked Picked Up')`, $$self{id} );
	} # end if
	return $$self{completed_on};
} # end sub completed_on
sub completed_on_seconds {
	return Date::Parse::str2time( $_[0]->completed_on() );
} # end sub completed_on_seconds

sub printed_on {
	my ( $self ) = @_;
	if ( ! exists $$self{printed_on} ) {
		@$self{printed_on} = sql::execute( undef, undef, q`SELECT MAX(dtmtimestamp) FROM Project_Log WHERE project_id=? AND description LIKE 'Marked Printed%'`, $$self{id} );
		if ( ! $$self{printed_on} ) {
			@$self{printed_on} = sql::execute( undef, undef, q`SELECT MAX(dtmtimestamp) FROM Project_Log WHERE project_id=? AND description LIKE 'Form % Completed for%'`, $$self{id} );
		}
	} else {
$openprint::log->debug("Printed on: $$self{printed_on}");
	} # end if
	return $$self{printed_on};
} # end sub printed_on

sub shipped_on {
	my ( $self ) = @_;
	if ( ! exists $$self{shipped_on} ) {
		@$self{shipped_on} = sql::execute( undef, undef, q`SELECT MAX(dtmtimestamp) FROM Project_Log WHERE project_id=? AND description IN ('Marked Shipped','Marked Picked Up')`, $$self{id} );
		if ( $$self{docket} and ! $$self{shipped_on} ) {
			my $ShippingLabel = openprint::Label->find_one( docket=>$$self{docket}, type=>'PackingSlip' );
			if ( $ShippingLabel ) {
				$$self{shipped_on} = $$ShippingLabel{created_on};
			}
		}
	} # end if
	return $$self{shipped_on};
}

sub printed_on_seconds {
	return Date::Parse::str2time( $_[0]->printed_on() );
} # end sub printed_on_seconds

sub approved_on {
	my ( $self ) = @_;
	if ( ! exists $$self{approved_on} ) {
		@$self{approved_on} = sql::execute( undef, undef, q`SELECT MAX(dtmtimestamp) FROM Project_Log WHERE project_id=? AND ( description like 'Marked Approved%' OR description like 'Marked Proofs QA Approved%' )`, $$self{id} );
	} # end if
	return $$self{approved_on};
} # end sub approved_on
sub approved_on_seconds {
	return Date::Parse::str2time( $_[0]->approved_on() );
} # end sub approved_on_seconds

sub proofsout_on {
	my ( $self ) = @_;
	if ( ! exists $$self{proofsout_on} ) {
		@$self{proofsout_on} = sql::execute( undef, undef, q`SELECT MAX(dtmtimestamp) FROM Project_Log WHERE project_id=? AND ( description LIKE 'Marked Proofs Out%' OR  description LIKE  'Marked Waiting for Customer Approval%' )`, $$self{id} );
	} # end if
	return $$self{proofsout_on};
} # end sub completed_on

sub proofsout_on_seconds {
	return Date::Parse::str2time( $_[0]->proofsout_on() );
} # end sub proofsout_on_seconds
#
sub production_seconds {
	my ( $self ) = @_;
	return $self->completed_on_seconds() - $self->approved_on_seconds();
} # end sub production_seconds

sub ordered_to_takeover_seconds {
	return $_[0]->takeover_on_seconds() - $_[0]->ordered_on_seconds();
} # end sub ordered_to_takeover_seconds
sub takeover_to_approved_seconds {
	return $_[0]->approved_on_seconds() - $_[0]->takeover_on_seconds();
} # end sub ordered_to_takeover_seconds
sub ordered_to_printed_seconds {
	return $_[0]->printed_on_seconds() - $_[0]->ordered_on_seconds();
} # end sub ordered_to_takeover_seconds

sub first_scheduled {
	my ( $self ) = @_;
	if ( ! exists $$self{first_scheduled} ) {
		@$self{first_scheduled} = sql::execute( undef, undef, q`SELECT MIN(dtmtimestamp) FROM Project_Log WHERE project_id=? AND (description LIKE 'Scheduled%' OR description LIKE '%bumped%' )`, $$self{id} );
	} # end if
	return $$self{first_scheduled};
} # end sub first_scheduled
sub first_scheduled_seconds {
	return Date::Parse::str2time( $_[0]->first_scheduled() );
} # end sub first_scheduled_seconds

sub last_scheduled {
	my ( $self ) = @_;
	if ( ! exists $$self{last_scheduled} ) {
		@$self{last_scheduled} = sql::execute( undef, undef, q`SELECT MAX(dtmtimestamp) FROM Project_Log WHERE project_id=? AND (description LIKE 'Scheduled%' OR description LIKE '%bumped%')`, $$self{id} );
	} # end if
	return $$self{last_scheduled};
} # end sub last_schedule
sub last_scheduled_seconds {
	return Date::Parse::str2time( $_[0]->last_scheduled() );
} # end sub last_scheduled_seconds

sub operator_id {
	my ( $self ) = @_;

	my ( $caller, undef, $line ) = caller;
	$openprint::log->error("deprecated call to Project::operator_id from $caller:$line");

	if ( ! $$self{operator_id} ) {
		my $services = $self->services();
		@$self{operator_id} = sql::execute( $log, $dbh, q{SELECT operator_id FROM tbl_Project_Contents WHERE lngProjectIndex=? AND lngServiceIndex=?}, $$self{id}, ( $$services{Proofs} ? $$services{Proofs}[0] : $$services{FilmStripping}[0] ) );
	} # end if
	return $$self{operator_id};
} # end sub operator_id

sub Operator {
	my ( $self ) = @_;

	my ( $caller, undef, $line ) = caller;
	$openprint::log->error("deprecated call to Project::operator_id from $caller:$line");

	if ( ! $$self{Operator} ) {
		$$self{Operator} = new openprint::User( $self->operator_id() );
	} # end if
	return $$self{Operator};
} # end sub Operator

sub delivery_cost {
	my ( $self ) = @_;

	my $qty_index = $self->ordered_quantity_index();

	if ( ! exists $$self{delivery_cost} ) {
		my $services = $self->services();
		foreach my $ServiceType ( openprint::ServiceType->find(category=>'Shipping') ) {
			next if ! $$services{$ServiceType->name()};
			foreach ( @{$$services{$ServiceType->name()}} ) {
				my $specs = openprint::service::get_specs_ref( $self, $_ );
				$$self{delivery_cost} += $$specs{'txtPrice'.$qty_index};	
			} # end foreach
		} # end foreach
	} # end if
	return $$self{delivery_cost};
} # end sub delivery_cost

sub production_cost {
	my ( $self ) = @_;


	if ( ! exists $$self{production_cost} ) {
		my @Shipping_Services = map { $_->name() } openprint::ServiceType->find(category=>'Shipping');
		my $services = $self->services();
		foreach my $ServiceType ( keys %$services ) {
			next if sets::isin( $ServiceType, \@Shipping_Services );
			foreach ( @{$$services{$ServiceType}} ) {
				my $specs = openprint::service::get_specs_ref( $self, $_ );
				$$self{production_cost} += $$specs{'txtPrice'.$self->ordered_quantity_index()};	
			} # end foreach
		} # end foreach
	} # end if
	return $$self{production_cost};
} # end sub production_cost

sub Service {
	my ( $self, $service_id ) = @_;
	if ( ! $service_id ) {
		$openprint::log->error("No service_id passed to Service for project $$self{id}");
		Carp::cluck("No service_id passwrod to Project::Service");
	} # end if
	if ( ! $$self{Project_Services}{$service_id} ) {
		$$self{Project_Services}{$service_id} = new openprint::Project_Service( {project_id=>$$self{id}, service_id=>$service_id} );
	}
	return $$self{Project_Services}{$service_id};
	#return new openprint::Project_Service( { service_id=>$service_id} );
} # end sub Service

sub used_press_names {
	my $self = $_[0];
	my @results;
	foreach my $service_id ( $self->signatures() ) {
		my $Service = $self->Service( $service_id );
		my $sig_specs = $Service->specs();
		if ( ! $$sig_specs{UsePress} ) {
			push @results, $$sig_specs{'ddmPress'.$self->ordered_quantity_index()};
		} else {
			push @results, $$sig_specs{UsePress};
		} # end if
	} # end foreach
	return sets::union( @results );	
} # end sub used_press_names

sub add_Service {
	my $service_id = $_[0]->add_service( $_[1] );
	return $_[0]->Service( $service_id );
} # end sub add_Service

sub recalculate {
	my $self = shift;
	$self->currency_id( $openprint::session{Currency_id} );
	my $Company = $self->Company();
	my $CSR = $Company->CSR();

	$$self{discount} = $$Company{discount};
	$$self{credit_card_fee} = $$Company{credit_card_fee};
	$$self{csr_commission} = defined $$Company{csr_commission} ? $$Company{csr_commission} : $$CSR{commission};

	my $services = $self->services();
	if ( $$services{''} ) {
		my $Type = $self->Type();
		$openprint::log->debug('Project::recalculate '.$$Type{type});
		my $specs = openprint::service::internal_calc( $openprint::log, $openprint::dbh, \%openprint::variable,
				$$self{id}, $$services{''}[0], $$Type{type} );
		my $status = $$specs{Status};
		$openprint::log->debug("Project::recalculate $$Type{type} $status");
		# Why is this ne calculated... if the project service can't calc... then neither can the signatures
		if ( $status eq 'calculated' ) {
			# Recalc signatures
			my $module = 'openprint::Estimating::'.$$Type{type};
			if ( my $function = $module->can('save') ) {
				$status = $function->($$self{id}, $$services{''}[0], {});
				$openprint::log->debug("$$Type{type}::save: status: $status");
      } else {
        $openprint::log->error("No calculate signatures function for $$Type{type}");
			} # end if
			if ( my $function = $module->can('calculate_signatures') ) {
				$status = $function->($self);
				$openprint::log->debug("$$Type{type}::Calculate_Sigs: status: $status");
				openprint::service::status($$self{id}, $$services{''}[0], $status);
      } else {
        $openprint::log->error("No calculate signatures function for $$Type{type}");
			} # end if
			openprint::service::auto_calculate($self, $$services{''}[0]) if $status eq 'calculated';
		} # end if
	} # end if
	$self->update_status();
	$self->summary(undef);
	foreach ( $self->quantity_indexes() ) { $self->price($_,undef); }
	$self->add_to_log( @openprint::session{'company_id','user_id'}, 'Recalculated. Prices: '.join(',', map { $openprint::Currency->format($_) } $self->prices() ) );
	return $self->save({calculated_on=>'NOW()'});
} # end sub recalculate

sub Project {
	return $_[0];
} # end sub Proejct;

sub calliper {
	if ( ! $_[0]{calliper} ) {
		my $Project = $_[0];
		my $services = $Project->services();
		my $project_type = $Project->Type()->type();

		my $printing_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] );

		my $finished_calliper = 0;

		my @quantity_indexes = $Project->quantity_indexes() ;
		if ( $project_type eq 'MultiPage' ) {

require openprint::Estimating::MultiPage;
	
			foreach my $group_id ( $$printing_specs{groups} ? split(',', $$printing_specs{groups} ) : openprint::Estimating::MultiPage::groups( $$Project{id}, $printing_specs ) ) {
				foreach my $signature_service_index ( $Project->signatures({Group=>$group_id}) ) {
					my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
					my $sig_caliper = $$sig_specs{txtSpecificStockCalliper} ? $$sig_specs{txtSpecificStockCalliper} : $$printing_specs{"txtSpecificStockCalliper$group_id"};
				
				$finished_calliper += int( 10000 * ($$printing_specs{'GroupPageQuantity'.$group_id}/2) * $sig_caliper );
				$log->debug("$finished_calliper += int( 10000 * (" . $$printing_specs{'GroupPageQuantity'.$group_id}.'/2) * '.$sig_caliper );
					last;
				}

			} # end foreach group
			if ( ! $finished_calliper ) {
				$log->error("Getting calliper the old way.");
				foreach my $signature_service_index ( $Project->signatures() ) {
					my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
					my $calliper = 0;
					if ( $$sig_specs{txtSpecificStockCalliper} ) {
						$calliper = int($$sig_specs{txtSpecificStockCalliper}*10000);
					} else {
						$openprint::log->warn("Loading calliper from stock.  Consider populating sig_specs with calliper for speed.");	
						my $Paper = openprint::Paper::load_from_signature( $Project, $sig_specs );
						$$sig_specs{txtSpecificStockCalliper} = $Paper->calliper();
						$calliper = int( $Paper->calliper() * 10000);
					} # end if

					foreach my $qty_index ( @quantity_indexes ) {
						if ( $$sig_specs{'PageQuantity'.$qty_index} ) {
							$calliper *= int($$sig_specs{'PageQuantity'.$qty_index}/2);
							last;
						} else {
							$openprint::log->warn("No PageQuantity in sig $signature_service_index");
						} # end if
					} # end foreach qty_index
					$finished_calliper += $calliper;
				} # end if
			} # en dif ! calliper
		} elsif ( $project_type eq 'ScratchPads' ) {
			my @signatures = $Project->signatures();
# Single page item, if there are multiple signatures, it is due to multiple versions
			my $signature_service_index = $signatures[0];
			my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
			my $calliper;
			if ( $$sig_specs{txtSpecificStockCalliper} ) {
				$calliper = int($$sig_specs{txtSpecificStockCalliper}*10000);
			} else {
				$openprint::log->warn("Loading calliper from stock.  Consider populating sig_specs with calliper for speed.");
				my $Paper = openprint::Paper::load_from_signature( $Project, $sig_specs );
				$$sig_specs{txtSpecificStockCalliper} = $Paper->calliper();
				$calliper = int( $Paper->calliper() * 10000);
			} # end if
			$finished_calliper += $$printing_specs{PageQuantity} * $calliper;
		} else {
			my @signatures = $Project->signatures();
# Single page item, if there are multiple signatures, it is due to multiple versions
			my $signature_service_index = $signatures[0];
			my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
			my $calliper;
			if ( $$sig_specs{txtSpecificStockCalliper} ) {
				$calliper = int($$sig_specs{txtSpecificStockCalliper}*10000);
			} else {
				$openprint::log->warn("Loading calliper from stock.  Consider populating sig_specs with calliper for speed.");	
				my $Paper = openprint::Paper::load_from_signature( $Project, $sig_specs );
				$$sig_specs{txtSpecificStockCalliper} = $Paper->calliper();
				$calliper = int( $Paper->calliper() * 10000);
			} # end if
			my $pages = 1;
			if ( $$sig_specs{rdbTemplateType} ) {
				if ( sets::isin( $$sig_specs{rdbTemplateType}, [ '2PanelFold', '4PageFold', 'Landscape Fold', 'Portrait Fold' ] ) ) {
					$pages = 2;
				} elsif ( sets::isin( $$sig_specs{rdbTemplateType}, [  'NoFold', 'Portrait', 'Landscape','Square','Forms', '' ] ) ) {
				} elsif ( sets::isin( $$sig_specs{rdbTemplateType}, [ 'PadsPortrait', 'PadsLandscape','PadsSquare','Pads' ] ) ) {
					$pages *= $$sig_specs{PageQuantity} if $$sig_specs{PageQuantity};
				} elsif ( sets::isin( $$sig_specs{rdbTemplateType},['3PanelFold','3PanelZFold'] ) ) {
					$pages = 3;
				} elsif ( sets::isin( $$sig_specs{rdbTemplateType}, ['4PanelFold', '4PanelZFold', '4PanelRollFold'] ) ) {
					$pages = 4;
				} elsif ( sets::isin( $$sig_specs{rdbTemplateType}, ['5PanelFold', '5PanelZFold'] ) ) {
					$pages = 5;
				} elsif ( sets::isin( $$sig_specs{rdbTemplateType}, ['6PanelFold', '6PanelZFold','12Page3PanelRollFold', '12Page3PanelZFold'] ) ) {
					$pages = 6;
				} elsif ( $$sig_specs{rdbTemplateType} eq 'SingleGateFold' ) {
					$pages = 3;
				} elsif ( sets::isin( $$sig_specs{rdbTemplateType}, [ 'DoubleGateFold', '2Panel2Pocket' ] ) ) {
					$pages = 4;
				} elsif ( $$sig_specs{rdbTemplateType} eq 'DifficultFold' ) {
					$pages = 6;
				} elsif ( $$sig_specs{rdbTemplateType} eq '8PageFold' ) {
					$pages = 4;
				} elsif ( $$sig_specs{rdbTemplateType} eq '2Panel1Pocket' ) {
# FIXME: GUTTERS
					$pages = 3;
				} elsif ( $$sig_specs{rdbTemplateType} eq '3Panel1Pocket' ) {
# FIXME: GUTTERS
					$pages = 4;
				} else {
					$log->error("Unknown template type n calliper $$sig_specs{rdbTemplateType}");
				} #// end if
			} elsif ( $$sig_specs{txtWidth} != $$sig_specs{txtFinalWidth} or $$sig_specs{txtHeight} != $$sig_specs{txtFinalHeight} ) {
				$log->error("No template given, but flat and final dimensions differ");
			}
			$finished_calliper += $pages * $calliper;
		} # end if
		$openprint::log->debug("******************************* FINISHED CALLIPER is $finished_calliper/1000 *********************************");
		$_[0]{calliper} = Math::Round::nearest( 0.0001, $finished_calliper/10000);
	} # end  if
	return $_[0]{calliper};
} # end sub calliper

sub Currency {
	return new openprint::Currency( $_[0]{currency_id} );
} # end sub Currency

sub change_ProjectType {
	my $error;
	my ( $Project, $ProjectType ) = @_;
   # This will likely never happen, because the act of cilcking on the different project type changes it.
	my $services = $Project->services();
	my $OldProjectType = $Project->Type();

# Handle ProjectType
	if ( $$Project{type_id} ) {
		if ( $OldProjectType->id() != $ProjectType->id() ) {
			if ( $$services{''} ) {
				foreach ( @{$$services{''}} ) { openprint::print_project::delete_service( $Project, $_ ); };
			} # end if
			delete $$services{''};
			if ( $OldProjectType->type() ne $ProjectType->type() ) {
				$log->debug('Removing sigs because project type is different');
				# Brochure to multipage or nice versa.  Have to remove sigs.
				foreach ( $Project->signatures() ) { openprint::print_project::delete_service( $Project, $_ ); }
				delete $$services{Signature};
			} else {
				$openprint::log->debug("Not Removing sigs because project type is same $$OldProjectType{type} == $$ProjectType{type}");
			} # end if
		} else {
			$openprint::log->debug("Not Removing sigs because project type is same $$OldProjectType{id} == $$ProjectType{id}");
		} # end if
	} # end if $$project{type_id}

  # Have to set it first because Service defaults depend upon it.
  $$Project{type_id} = $ProjectType->id();

	if ( $$Project{id} ) {
		if ( ! $$services{''} ) {
			my $printing_service_index = openprint::print_project::insert_project_type( $openprint::r, $openprint::log, $openprint::dbh, $$Project{id}, $ProjectType->name() );
			push @{$$services{''}}, $printing_service_index;
		} # end if
		my %oldRequiredServiceTypes = map { $$_{name} => $_ } $OldProjectType->required_ServiceTypes();
		my %newRequiredServiceTypes = map { $$_{name} => $_ } $ProjectType->required_ServiceTypes();

	# Remove no longer needed services
		foreach my $service_type_name ( keys %oldRequiredServiceTypes ) {
			if ( ! $newRequiredServiceTypes{$service_type_name} ) {
				foreach my $s_id ( @{$$services{$service_type_name}} ) {
					openprint::print_project::delete_service($Project, $s_id);
				} # end foreach
				delete $$services{$service_type_name};
			} # end if
		} # end foreach

	# add needed services
		foreach my $service_type_name ( keys %newRequiredServiceTypes ) {
			if ( ! $$services{$service_type_name} ) {
				my $s_id = $Project->add_service($newRequiredServiceTypes{$service_type_name});
				push @{$$services{$service_type_name}}, $s_id;
			} # endif
		} # end foreach
    $log->debug("Saving project type_id $$ProjectType{id}");
		$error .= $Project->save();
	} else {
		$log->debug('Do not have project id, just setting type_id');
	} # end if
	return $error;
} # end sub change_ProjectType

sub url_to {
	return '/main/proj/view.html?pid='.$_[0]{id};
} # end sub url_to

sub link_to {
	return sprintf('<a href="%1$s?pid=%2$d">%3$s</a>', $_[0]->url_to(), $_[0]{id}, ( $_[1] ? $_[1] : $_[0]{id} ) );
} # end sub link_to

sub production_link_to {
	return sprintf('<a href="/employee/project/view.html?project_id=%1$d">%2$s</a>', $_[0]{id}, ( $_[1] ? $_[1] : $_[0]{id} ) );
} # end sub production_link_to

sub check_for_order {
	my ( $Project, $OP ) = @_;

	my $error = '';

	if ( $$Project{status} eq 'uncalculated' ) {
		$error .= 'Project ' . $$Project{id} . ' is uncalculated.  Please resolve this before continuing your order.<br/>';
	} # end if
	my $last_calculated = Date::Parse::str2time( $Project->calculated_on() );
	if ( $openprint::config{QuoteValidDays} and ( time - $last_calculated ) > $openprint::config{QuoteValidDays} * 24*60*60 ) {
		$error .= 'Project ' . $$Project{id} . ' is too old.  Please recalculate it to update pricing before continuing your order.<br/>';
	} # end if
	my $services = $Project->services();
	my $stock_index = $$services{Paper} ? $$services{Paper}[0] : 0;

	if ( $stock_index ) {
		my $Stock_Service = $Project->Service( $stock_index );
		my @Stock_Quantities = openprint::Estimating::Paper::get_stocks_and_quantities( $Project, $stock_index, $Stock_Service->specs(), $OP->quantity_index() );
		if ( @Stock_Quantities ) {
			foreach my $Stock_Qty ( @Stock_Quantities ) {
				my $Stock = $$Stock_Qty{Stock};
				$openprint::log->debug("Quantity for " . $Stock->to_string() . ' is ' . $$Stock_Qty{quantity} ) if $debug;
				if ( defined $Stock->available_to_order() ) {
					my $allocated = misc::sum( map { $_->quantity() } openprint::PaperAllocation->find(docket=>$Project->docket(), paper_id=>$$Stock{id}) );

					if ( $Stock->available_to_order()+$allocated < $$Stock_Qty{quantity} ) {
						$error .= 'There is not enough stock available to satisfy this order.  Please contact your CSR.<br/>';
					} # end if
				} # end if
			} # end foreach Stock   
		} elsif ( $debug ) {
			$openprint::log->debug("No stock quantities.");
		} # end if  
	} elsif ( $debug ) {
		$openprint::log->debug("Not Paper service in project $$Project{id}");
	} # end if Stock Service Index
 
	return $error;
} # end sub check_for_order

sub allocate_for_order {
	my ( $Project, $OP ) = @_;
    my $error = '';

    my $services = $Project->services();
    my $stock_index = $$services{Paper} ? $$services{Paper}[0] : 0;

    if ( $stock_index ) {
        my $Stock_Service = $Project->Service( $stock_index );
        my @Stock_Quantities = openprint::Estimating::Paper::get_stocks_and_quantities( $Project, $stock_index, $Stock_Service->specs(), $OP->quantity_index() );
        if ( @Stock_Quantities ) {
            foreach my $Stock_Qty ( @Stock_Quantities ) {
                my $Stock = $$Stock_Qty{Stock};
                $openprint::log->debug("Quantity for " . $Stock->to_string() . ' is ' . $$Stock_Qty{quantity} ) if $debug;
                if ( $Stock->available_to_order() > $$Stock_Qty{quantity} ) {
					$Stock->allocate( undef, $OP->Order(), $$Stock_Qty{quantity}, undef );
				} else {
					$error .= 'Not enough stock available to allocate.<br/>';
                } # end if
            } # end foreach Stock   
        } elsif ( $debug ) {
            $openprint::log->debug("No stock quantities.");
        } # end if  
    } elsif ( $debug ) {
        $openprint::log->debug("Not Paper service in project $$Project{id}");
    } # end if Stock Service Index

    return $error;
} # end sub allocate_for_order

sub finished_weight {
	my $project_weight;

	my $Project = $_[0];
# We do a weird thing with qty_index here, becasue all quantities should have the same weight, but may be calculated diferent ways, so we run through them until we get a valid weight.

# calculate project weight
	foreach my $qty_index ( $Project->quantity_indexes() ) {

		foreach my $signature_service_index ( $Project->signatures() ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
			next if $$sig_specs{txtSignatureType} and ! $$sig_specs{'PageQuantity'.$qty_index};
			next if ! $$sig_specs{'txtImposition'.$qty_index};
			my $sig_weight = openprint::Estimating::Printing::get_weight( $Project, $sig_specs, $qty_index );
			if ( ! $sig_weight ) {
# unable to get weight for a sig, must recalc printing service
				$openprint::log->error("Unable to get sig_weight for signature $$sig_specs{SignatureIndex}");
				return 0;
			} elsif ( $debug ) {
				$openprint::log->debug("Sig weight for sig $$sig_specs{SignatureIndex} $sig_weight");
			} # end if
			$project_weight += $sig_weight;
		} # end foreach signature_service_index
		last;
	} # end foreach qty_index
#$openprint::log->debug("Project Weight: $project_weight : Marked Up: ". $project_weight * (1+$openprint::config{WeightMarkup}/100));

# This 1.1 was actually requested by Amin.  So it was pretty random, but then I thought abotu it, and our weight calculations don't take into account the weight of the ink, etc... so it may actually be not too off.... would love to see some real figures on it.
	return $project_weight * (1+$openprint::config{WeightMarkup}/100);
} # end sub finished_weight

sub can_view {
	if ( ! $_[0]{id} ) {
		$openprint::log->debug("can_view 1 cuz no id") if $debug;
		return 1;
	}
	if ( $openprint::session{user_type} eq 'A' ) {
		$openprint::log->debug("can_view 1 cuz admin") if $debug;
		return 1 
	}
	if ( $openprint::session{company_id} == $_[0]{company_id} ) {
		$openprint::log->debug("can_view 1 cuz i am the company") if $debug;
		return 1;
	}

	if ( sets::isin( $_[0]{user_id}, [ $$openprint::User{id}, $openprint::User->assistant_ids(), $openprint::User->csr_ids() ] ) ) {
		$log->debug("$$openprint::User{firstname} Either created it or is an assistant") if $debug;
		return 1;
	} else {
		$log->debug("$_[0]{user_id} != $$openprint::User{id}") if $debug;
	} # end if
	if ( openprint::usergroup::is_user_in( ['Accounting', 'Estimating'], $openprint::session{user_id} ) ) {
		return 1;
	}
	return 0;
}

sub can_edit {
	if ( ! $_[0]{id} ) {
		$openprint::log->debug("can_view 1 cuz no id") if $debug;
		return 1;
	}

  if ( $_[0]{user_id} == $openprint::session{user_id} ) {
		$openprint::log->debug("can_view 1 cuz i am the creator") if $debug;
		return 1;
	}
  #if ( $openprint::session{company_id} == $_[0]{company_id} ) {
  #$openprint::log->debug("can_view 1 cuz i am the company") if $debug;
  #return 1;
  #}
	if ( $openprint::session{user_type} eq 'A' ) {
		$openprint::log->debug("can_edit 1 cuz admin") if $debug;
		return 1 
	}
	if ( sets::isin( $_[0]{user_id}, [ $openprint::User{id}, $openprint::User->assistant_ids(), $openprint::User->csr_ids() ] ) ) {
		$log->debug("$openprint::User{firstname} Either created it or is an assistant") if $debug;
		return 1;
	} # end if
  
  return 0;
} # end sub can_edit

sub can_delete {
  my $self = shift;
  if ( $$self{user_id} == $openprint::session{user_id} ) {
    $openprint::log->debug("can_view 1 cuz i am the creator") if $debug;
    return 1;
  }
  if ($$self{company_id} == $openprint::session{company_id}) {
    $openprint::log->debug("can_view 1 cuz i am the company") if $debug;
    return 1;
  }
  if ( $openprint::session{user_type} eq 'A' ) {
    $openprint::log->debug('can_edit 1 cuz admin') if $debug;
    return 1
  }
  return 0;
}

sub change_due_date {
	my $Project = shift;
	my $new_due_date = shift;

	my $old_due_date = $$Project{due_date};
	if ( $old_due_date ne $new_due_date ) {
		$Project->save( { due_date => $new_due_date } );
		$Project->add_to_log( @openprint::session{'company_id','user_id'}, "Duedate changed to $new_due_date from $old_due_date" );
		openprint::employee_project::send_duedate_change_notification( $$Project{id}, $Project->order_id() );
	} # end if date has changed
}

sub Services {
	my $self = shift;
	$$self{Project_Services} = shift if @_;
	if ( $$self{id} and !$$self{Services} ) {
		%{$$self{Project_Services}} = map { $$_{service_id} => $_ } openprint::Project_Service->find(project_id=>$$self{id});
	}
	return values %{$$self{Project_Services}} if $$self{Project_Services};
	return ();
}

sub credit_card_fee {
  my $self = shift;
  if ( @_ ) {
    my $qty_index = shift;
    if ( ! exists $$self{'credit_card_fee'.$qty_index} ) {
      my $price = $self->price($qty_index);
      $$self{'credit_card_fee'.$qty_index} = $price - ( $price/( 1+($$self{credit_card_fee}/100) ) )
    }
    return $$self{'credit_card_fee'.$qty_index};
  }
  $$self{credit_card_fee} = shift if @_;
  return $$self{credit_card_fee};
} # end sub credit_card_fee

sub csr_commission {
# Commissions are paid on the project cost NOT including credit card processing fees
	my $self = shift;
	if ( @_ ) {
		my $qty_index = shift;
		if ( ! exists $$self{'csr_commission'.$qty_index} ) {
			my $price = $self->price($qty_index) - $self->credit_card_fee($qty_index);
			$$self{'csr_commission'.$qty_index} = $price - ( $price/( 1+($$self{csr_commission}/100) ) )
		}
		return $$self{'csr_commission'.$qty_index};
	}
	$$self{csr_commission} = shift if @_;
	return $$self{csr_commission};
} # end sub csr_commission

sub get_book_type {
  my $Project = shift;
  my $services = $Project->services();

# the way we cut down the book depends on how it is being bound, so we need this for the signature information.
  foreach my $service ( 'SaddleStitching', 'LoopStitching', 'PerfectBound','SpinePaste','Spiral','MetalCoil','PlasticCoil','DoubleLoopWire','Cerlox','Unbound' ) {
    if ( $$services{$service} ) {
      return $service;
    } # end if
  } # end foreach

  if ( $$services{''} and @{$$services{''}} ) {
    my $printing_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] );
    if ( $$printing_specs{rdbTemplateType} and ( $$printing_specs{rdbTemplateType} eq 'PerfectBound' ) ) {
      return 'PerfectBound';
    } # end if
  } # end if
  return;
} # end sub get_book_type

sub is_fsc {
	my $self = shift;	
	foreach my $sig_id ( $self->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $self, $sig_id );
		my $Paper = openprint::Paper::load_from_signature( $self, $sig_specs );
		if ( $Paper->is_fsc() ) {
			return 1;
		}
	}
	return 0;
}
sub stock_name {
  my $self = shift;
  my $services = $self->services();
  if ($$services{Paper}) {
    return join('<br/>', openprint::Estimating::Paper::summary($self, $$services{Paper}[0]));
  }
}

sub ink_sum {
  my $self = shift;
  my $services = $self->services();
  my $ink_sum = '';
  my $printing_specs = openprint::service::get_specs_ref( $self, $$services{''}[0] );


  my @groups = sql::execute( undef, undef, 'SELECT DISTINCT strvalue FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND strName=?', $$self{id}, 'Group' );
  if (@groups) {
# I believe the point of this is to stick the Printed Web or Sheetfed into the summary. Nastily executed.
# The logic is, each group has to be either all sheetfed, or all web (or digital, etc). 
    foreach my $group_id ( sort @groups ) {
      my @sigs = $self->signatures({Group=>$group_id});
      if ( ! @sigs ) {
        $openprint::log->error( "No sigs for Group $group_id, but there pretty much to be since we have this group index.  Signatures must be out of date");
      } # end if

      my $sig_specs = openprint::service::get_specs_ref( $self, $sigs[0] );
      $ink_sum .= openprint::Estimating::Printing::get_colour_description_no_coverage($self, $sig_specs);
    }
  } else {
    my @sigs = $self->signatures();
    my $sig_specs = openprint::service::get_specs_ref( $self, $sigs[0] );
    $ink_sum .= openprint::Estimating::Printing::get_colour_description_no_coverage($self, $sig_specs);
  }

  return $ink_sum;
}

sub parent_sheet_count {
  my $self = shift;
  my $services = $self->services();
  if ($$services{Paper}) {
    return join('<br/>', openprint::Estimating::Paper::summary($self, $$services{Paper}[0], undef, $self->ordered_quantity_index()) );
  }
}

sub dims_finished {
  my $self = shift;
  my $services = $self->services();
  if ( $$services{''} and @{$$services{''}} ) {
    my $printing_specs = openprint::service::get_specs_ref( $self, $$services{''}[0] );
    return $$printing_specs{txtWidth}.'x'.$$printing_specs{txtHeight};
  }
  foreach my $sig_id ($self->signatures()) {
    my $printing_specs = openprint::service::get_specs_ref($self, $sig_id);
    return $$printing_specs{txtWidth}.'x'.$$printing_specs{txtHeight};
  }
  return 'unknown';
}

sub equipment {
  my $self = shift;
  my %equipment;
	foreach my $sig_id ( $self->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $self, $sig_id );
    $equipment{$$sig_specs{'ddmPress'.$self->ordered_quantity_index()}} = 1;
	}
  return join(', ', keys %equipment);
}

1;
__END__
