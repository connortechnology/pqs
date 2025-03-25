use strict;
use warnings;
package openprint::order;

require Email::Valid;
require Date::Calc;
require Math::Round;

use openprint ();
use vars qw( %param %variable %config %session $log $dbh );
*param = \%openprint::param;
*variable = \%openprint::variable;
*config = \%openprint::config;
*session = \%openprint::session;
*log = \$openprint::log;
*dbh = \$openprint::dbh;

use constant DEBUG => 0;

require sql;
require openprint::Currency;
require openprint::service;
require openprint::Order;
require openprint::OrderedProduct;
require openprint::usergroup;
require openprint::press_schedule;
require openprint::Payment;
require openprint::PaperAllocation;
require openprint::Company_Credit;

sub delete_unfinished_orders {
	# clean out old orders
	my $ac = sql::start_transaction( $dbh );
	foreach my $Order ( openprint::Order->find('session_id'=>$session{_session_id},'status'=>'Incomplete') ) {
		$Order->delete();
	} # end foreach
	sql::update( $log, $dbh, 'Orders', ['strSessionID=?', $session{_session_id}], 'strSessionID', undef );
	sql::end_transaction( $dbh, $ac );
} # end sub delete_unfinished_orders

sub get_unfinished_order {
	# This also tests for existence of the order
	if ( $session{order_id} ) {
		my $Order = openprint::Order->find_one( id=>$session{order_id} );
		return $Order->id() if $Order;
	} # end if

	my $Order = openprint::Order->find_one( session_id=>$session{_session_id}, company_id=>$session{company_id}, status=>'Incomplete', order=>'id DESC' );

	if ( $Order ) {
		$session{order_id} = $Order->id();
		return $Order->id();
	} # end if

	return;
} # end sub get_unfinished_order

sub get_order_id {
	my ( $order ) = sql::execute( $log, $dbh, 'SELECT MAX(Id) FROM Orders' );

	$order =~ /(\d\d\d\d)/;
	if ( $1 != ( 1900 + (localtime(time))[5] ) or $order eq '' ) {
		return 1900 + (localtime(time))[5] . '0001';
	} # end if
	return $order + 1;
} # end sub get_order_id

sub add_product {
	my ( $order_id, $product_id, $quantity ) = @_;

	my $error = '';

	return if check_credit( );

	$order_id = get_unfinished_order( ) if ! $order_id;
  my $Order;
  if (! $order_id) {
    $Order = create_order();
    $order_id = $Order->id();
  } else {
    $Order = new openprint::Order($order_id);
  }

	my $Ordered_Product;
	if ( my @Products = openprint::OrderedProduct->find( order_id=>$order_id, product_id=>$product_id ) ) {
		$Ordered_Product = shift @Products;
		# The logic here used to be that we would increase the quantity, but now we are thinking that we will reset the quantity.  Since this would really only happen on a reload anyways.  
	} else {
		my $Product = openprint::Product->find_one(id=>$product_id);
		if ( ! $Product ) {
			return ( $order_id, "Product $product_id not found." );
		}
		$Ordered_Product = new openprint::OrderedProduct();
		$Ordered_Product->product_id( $product_id );
		$Ordered_Product->order_id( $order_id );
	} # end if	
	$Ordered_Product->quantity( $quantity );
	$error .= $Ordered_Product->save();

	# Make the object reload its stored cache of Products
	$Order->Products(undef);

	my $Project = $Ordered_Product->Project();
	if ( $Project ) {
		$Project->order_id( $order_id );
		$Project->quantity1( $Ordered_Product->quantity() );
		foreach my $service_index ( sql::execute( undef, undef, q{SELECT lngServiceIndex FROM tbl_Project_Contents WHERE lngProjectIndex=?}, $Project->id() ) ) {
			openprint::service::insert_service_spec( $log, $dbh, $Project->id(), $service_index, 'txtQuantity1', $Project->quantity1() );
		} # end foreach
		$error .= $Project->recalculate();
	$log->debug("E: $error") if $error;
		if ( $Project->status() ne 'Unordered' ) {
			return ( $order_id, 'There is a problem with this product.  Please contact customer support.' );
		} # end if
	} # end if

	return ( $order_id, $error );
} # end sub add_product

# Assumptions
# We may or may not be logged in.
# We may or may not be logged in as the owner of the project.
# Project ownership will not change.
# Order ownership should not change, instead we should create a new order.

sub add_project_to_order {
	my ( $Project, $order_id ) = @_;
	my $error = '';

	if ( ! $Project->id() ) {
		return ( undef, 'No project given.' );
	} # end if

	if ( $Project->company_id() and ( $Project->company_id() != $session{company_id} ) ) {
# Switch company to the owner of the project
# FIXME Should do some authentication to ensure that we can
		openprint::switch_company( $Project->Company() );
		$variable{warning} .= 'You were not logged in as the owner of the project.  Your company has been changed to ' . $Project->Company()->name().'.';
	} # end if

	# Can't check an amount, because we havn't selected the quantity to order yet
	if ( check_credit( ) ) {
		return (undef, 'No more credit.');
	}

	$order_id = get_unfinished_order( ) if ! $order_id;
	# get unfinished no longer looks for re-opened orders.

	if ( ! $order_id ) {
		my @Orders = openprint::Order->find(company_id=>$session{company_id}, 'status'=>'Re-Opened', 'order'=>'id DESC' );
		if ( @Orders ) {
			$error .= 'There are Re-Opened orders.  Please select the existing order or a new order by clicking on the appropriate option.<br/>';
			$error .= qq`<a href="/main/order/information.html?order_id=New&amp;ProjectIndex=$$Project{id}&amp;btnFunction=Process%20Order">New Order</a><br/><br/>`;
			foreach my $Order ( @Orders ) {
				$error .= qq`<a href="/main/order/information.html?order_id=$$Order{id}&amp;ProjectIndex=$$Project{id}&amp;btnFunction=Process%20Order">Order $$Order{id} Docket $$Order{docket}`;
				my @Contents = $Order->Contents();
				if ( @Contents ) {
					$error .= ' Containing the following:<br/>';
					foreach my $C ( @Contents ) {
						$error .= 'Project ' . $C->project_id() . ' ' . $C->Project()->reference() . '<br/>' . $C->Project()->summary().'<br/>';
					} # end foreach
				} else {
					$error .= ' empty';
				} # end if
				$error .= '</a><br/><br/>';	
			} # foreach
			return ( undef, $error );
		} # end if
	} # end if

  my $Order;
	if ( ( ! $order_id ) or ($order_id eq 'New') ) {
		$Order = create_order();
    $order_id = $Order->id();
$log->debug("Creating order $order_id");
	} else {
$log->debug("NOT Creating order $order_id");
    $Order = openprint::Order->find_one( id=>$order_id );
	} # end if
	if (!($Order and $Order->id())) {
		$log->error("Failure to load order $order_id");
		return ( undef, "Failure to create order");
	}
	if ( ! $Project->company_id() ) {
		if ( $session{company_id} ) {
			# Will be saved later.
			$Project->company_id($session{company_id});
		} # end if
	} elsif ( $Order->company_id() != $Project->company_id() ) {
		$log->error("SHOULD NEVER HAPPEN order company ( $$Order{company_id}) != Project company ($$Project{company_id})");
		if ( ! $Order->Projects() ) {
			$variable{warning} .= 'Project is owned by ' . $Project->Company()->name() . ' but order is owned by ' . $Order->Company()->name().". The order is empty, so it's owner has been switched to " . $Project->Company()->name().'.';
			$variable{error} .= $Order->save({
					company_id	=>	$Project->company_id(),
					salesrep_id	=>	$Project->Company()->salesrep_id(),
					});
		} else {
			foreach my $P ( $Order->Projects() ) {
				$log->debug("Contains " . $P->reference() );
			}
			return ( $order_id, 'Project is owned by ' . $Project->Company()->name() . ' but order is owned by ' . $Order->Company()->name() );
		} # end if
	} # end if
	if ( $Project->order_id() and ( $Project->order_id() != $order_id ) ) {
		if ( $Project->Order()->status() eq 'Incomplete' ) {
			my $OP = new openprint::OrderedProject({order_id=>$$Project{order_id}, project_id=>$$Project{id}});
			$error .= $OP->delete();
		} else {
			return ( $order_id, sprintf('Project is already in order <a href="/main/order/history_details.html?order_id=%1$d">%1$d</a>.', $Project->order_id() ) );
		} # end if
	} # end if

	my %sql = (
		OrderIndex		=>	$order_id,
		lngProjectIndex	=>	$$Project{id},
		);

	my @qtys = $Project->quantity_indexes();
	if ( 1 == scalar @qtys ) {
		$sql{intQuantityIndex} = $qtys[0];
	} # end if
	my $services = $Project->services();
	if ( $$services{Turnaround} ) {
		my $specs = openprint::service::get_specs_ref( $Project, $$services{Turnaround}[0] );
		my ( $year, $month, $day ) = Date::Calc::Today();
		( $year, $month, $day ) = Date::Calc::Add_Delta_Days( $year, $month, $day, $$specs{TurnaroundDays} );
		if ( Date::Calc::Day_of_Week( $year, $month, $day ) == 6 ) {
			( $year, $month, $day ) = Date::Calc::Add_Delta_Days( $year, $month, $day, 2 );
		} elsif ( Date::Calc::Day_of_Week( $year, $month, $day ) == 7 ) {
			( $year, $month, $day ) = Date::Calc::Add_Delta_Days( $year, $month, $day, 1 );
		} # end if
		$sql{dateRequired} = join('-', $year, $month, $day );
	} # end if
	my @ShippingServices = openprint::ServiceType->find('category'=>'Shipping');
	if ( @ShippingServices ) {
		foreach my $ShippingType ( @ShippingServices ) {
			next if sets::isin( $ShippingType->name(), ['Turnaround'] );
			if ( $$services{$ShippingType->name()} ) {
				$sql{ShippingType}=$ShippingType->name();
				last;
			} # end if
		} # end foreach
if ( 0 ) {
# Stop defaulting to CP
		if ( ! $sql{ShippingType} ) {
			$sql{ShippingType} = 'CustomerPickUp';
		} # end if
} # end if
	} else {
		$sql{ShippingType}='CustomerPickUp';
	} # end if

	my $ac = sql::start_transaction( $dbh );
	$dbh->do( 'LOCK TABLE Order_Contents IN SHARE ROW EXCLUSIVE MODE' ) or $log->error( DBI->errstr );
				
	# make sure project isn't already in any order.
	map { $_->delete() } openprint::OrderedProject->find(project_id=>$$Project{id});

	sql::insert( $log, $dbh, 'Order_Contents', \%sql );
	sql::end_transaction( $dbh, $ac );
	
	$error .= $Project->save({
			order_id	=>	$order_id,
			});

	add_to_log( $log, $dbh, $order_id, @session{'company_id','user_id'}, "Add Project $$Project{id}" );
	$Project->add_to_log( @session{'company_id','user_id'}, "Add to Order $order_id" );
	delete $$Order{Projects};

	return ( $order_id, $error );
} # end sub add_project_to_order


# creates a new order
# attempts to copy data from the specified quote into the order.
# does NOT verify that the quote exists.
# does NOT delete the quote
sub make_order_from_quote {
	my ( $quote_id ) = @_;
	my $error = '';

  my $Quote = openprint::Quote->find_one(id=>$quote_id);
  if (!$Quote) {
    return (undef, 'Invalid quote specified');
  }

	my $Order = create_order();
  my @contents;

  foreach my $QP ($Quote->Projects()) {
		my $OP = new openprint::OrderedProject();
		$error .= $OP->save({
			order_id	=>	$Order->id(),
			project_id	=>	$QP->project_id(),
      #quantity	=>	$QP->quantity(),
      #price		=>	$QP->price(),
		});
		push @contents, $OP;
  }

    #if ( @quote > 0 ) {
    #foreach my $project_index ( @quote ) {
    #( $order_id, $_ ) =	add_project_to_order( new openprint::Project( $project_index ), $order_id );
    #$error .= $_;
    #} # end foreach
    #} # end if

	
	foreach my $QP ( $Quote->Products() ) {
		my $OP = new openprint::OrderedProduct();
		$error .= $OP->save({
			order_id	=>	$Order->id(),
			product_id	=>	$QP->product_id(),
			quantity	=>	$QP->quantity(),
			price		=>	$QP->price(),
		});
		push @contents, $OP;
	}

	if (!@contents) {
		$error .= "make_order_from_quote: Empty quote specified: $quote_id";
		$log->debug( "make_order_from_quote: Empty quote specified: $quote_id" );
	}
	return ( $$Order{id}, $error );
} # end sub make_order_from_quote

sub check_credit {
	my ( $amount ) = @_;
	my $Credit = new openprint::Company_Credit( { 'company_id'=>$openprint::session{company_id}, 'supplier_id'=>$openprint::config{owner_id} } );

	if ( $Credit->hold() and ( $Credit->hold() eq 'Y' ) ) {
		return misc::error( $log, $dbh, \%variable, 'Credit on hold', 'Your credit account is on hold, you will not be able to place orders.' );
	} # end if

	if ( $config{EnforceCredit} eq 'Y' ) {
		if ( ! $Credit->denydays() ) {
			if ( $Credit->debt() > 0 ) {
				my $error = 'Because you do not have a credit account, your previous order must be paid in full before another order is placed.	Click <a href="/account/credit_application.html">here</a> to apply for a credit account now.';
				$error .= list_orders( $log, $dbh, $Credit->denied_orders() );
				return misc::error( $log, $dbh, \%variable, 'No Credit', $error );
			} # end if
		} else {
			if ( my @orders = $Credit->denied_orders() ) {
				my $error = 'You have orders that are more than ' . $Credit->denydays() . ' days overdue.	Please arrange payment before purchasing further.<br/><br/>The following orders are currently overdue:<br/><br/>';
				$error .=	list_orders( $log, $dbh, @orders );
				return misc::error( $log, $dbh, \%variable, 'Overdue Orders', $error );
			} # end if

# check if the price fits in their credit limit
			if ( $Credit->debt() + $amount > $Credit->limit() ) {
				my $error = 'This order would exceed your remaining credit balance.	Please make a payment before placing another order.	To apply for additional credit click <a href="/account/credit_application.html">here</a>.<br/><br/>The following orders are still outstanding:<br/><br/>';
				$error .= list_orders( $log, $dbh, $Credit->outstanding_orders() );
				return misc::error( $log, $dbh, \%variable, 'Credit Exceeded', $error );
			} # end if
		} # end if
	} # end if EnforceCredit eq 'Y'
} # end sub check_credit

sub add_to_order {
	my ( $log, $dbh, $order_id, $variable, @data ) = @_;

# add items
	for (my $index = 0; $index < @data; $index += 2) {
		sql::insert( $log, $dbh, 'Order_Contents', (
					'OrderIndex', 		$order_id,
					'lngProjectIndex',	($data[$index] or undef),
					'intQuantityIndex', ($data[$index + 1] ne '' ? $data[$index + 1] : undef), # actually quantity can't be NULL.
					) );
		my $Project = new openprint::Project( $data[$index] );
		$Project->order_id( $order_id );
		$Project->save();
	} # end for
	return $order_id;
} # end sub add_to_order

sub create_order {
	my $ac = sql::start_transaction( $dbh );
	$dbh->do('LOCK TABLE Orders IN SHARE ROW EXCLUSIVE MODE') or $log->error(DBI->errstr);

	my $Order = new openprint::Order();
	$_ = $Order->save({
		user_id		=>	$session{user_id},
		company_id	=>	$session{company_id},
		session_id	=>	$session{_session_id},
		created_on	=>	'NOW()',
		status		=>	'Incomplete',
		salesrep_id	=>	$openprint::Company->salesrep_id(),
		currency_id	=>	$openprint::Currency->id(),
		});

	$Order->add_log('Created') if ! $_;

# unlock database
	sql::end_transaction($dbh, $ac);

	return $Order;
} # end sub create_order 

# the data array has the following row form: productindex, quantity, price
sub make_order {
	my ( $log, $dbh, $cookie, $variable, @data ) = @_;

# this goes before get_order_id so we re-use order_id's
	delete_unfinished_orders();

	my $Order = create_order( );
  my $order_id = $Order->id();
# add items
	add_to_order( $log, $dbh, $order_id, $variable, @data );
	return $order_id;
} # end sub make_order

# Now takes an OrderedProject or Product object
# Need to document what exactly this should be saving.
# For projects with multiple quantities, it should save the quantity selection
sub save_project_information {
	my ( $OP ) = @_;

	my $error;
	my $Project = $OP->Project();
	my $project_index = $OP->project_id();
	my $Order = $OP->Order();

	if ( $param{"rdbQuantity$project_index"} ) {
		$OP->quantity_index( $param{"rdbQuantity$project_index"} );
	} elsif ( ! $OP->quantity_index() ) {
		# Ordered Products don't have quantity_index field, so this is a NOP
		my @qtys = $Project->quantity_indexes();
		if ( 1 == scalar @qtys ) {
			$OP->quantity_index( $qtys[0] );
		} # end if
	} # end if



	# If we are specifying the Shipping Type
	if ( $param{'ShippingType'.$project_index} ) {
		my $quantity_shipped = $Project->ordered_quantity();
		my @ServiceTypes = openprint::ServiceType->find( category=>'Shipping');
		my $services = $Project->services();
		my $ProjectCurrency = $Project->Currency();
		$log->debug("ServiceTypes: " . join(',',map { $_->name() } @ServiceTypes )) if DEBUG;
		foreach my $ShippingType ( @ServiceTypes ) {

			# Add or delete services as relevant
			if ( sets::isin( $ShippingType->name(), $param{'ShippingType'.$project_index} ) ) {
				if ( ! $$services{$ShippingType->name()} ) {
					my $new_service_index = $Project->add_service( $ShippingType );
					push @{$$services{$ShippingType->name()}}, $new_service_index;
				} # end if
			} elsif ( $$services{$ShippingType->name()} ) {
				require openprint::print_project;
				# Thismight delete bindery shipping 
				foreach ( @{$$services{$ShippingType->name()}} ) {
					openprint::print_project::delete_service( $Project, $_ );
				} # end foreach
				delete $$services{$ShippingType->name()};
			} # end if

			next if ! $$services{$ShippingType->name()};

			my @shipping_fields = (
					'txtQuantity'.$Project->ordered_quantity_index(),
					( ! sets::isin( $ShippingType->name(), ['CustomerPickUp'] ) ? 
					  (
					   'ToCompanyName',
					   'ToSalutation',
					   'ToFirstName',
					   'ToLastName',
					   'ToAddress1',
					   'ToAddress2',
					   'ToCity',
					   'ToStateProvince',
					   'ToCountry',
					   'ToPostalCode',
					   'ToPhone',
					   'ToFax',
					   'ToEmail', ) : () ),
					);
			foreach my $service_id ( @{$$services{$ShippingType->name()}} ) {
				foreach my $spec ( @shipping_fields ) {
					my $key = join('-', $spec, $project_index, $service_id);
					$log->debug("Sacing: $$ShippingType{name} $key => " . ($param{$key}?$param{$key}:'') );
					openprint::service::insert_service_spec($log, $dbh, $project_index, $service_id, $spec, $param{$key}) if exists $param{$key};
				} # end foreach field
			} # end foreach service_id
		} # end foreach ShippingType
		foreach my $ShippingType ( @ServiceTypes ) {
			next if ! $$services{$ShippingType->name()};
			foreach my $service_id ( @{$$services{$ShippingType->name()}} ) {
				# Calculations will be in the current Currency.  Current currency will be the same as the Orders, but not neccessarily the same as the projects.

				my $specs = openprint::service::internal_calc( $log, $dbh, \%variable, $project_index, $service_id, $ShippingType->name(), $Project->ordered_quantity_index() );

				# Fix currency
				openprint::service::insert_service_spec( $log, $dbh, $project_index, $service_id, 'txtPrice'.$OP->quantity_index(), $Order->Currency()->convert_to( $ProjectCurrency, $$specs{'txtPrice'.$OP->quantity_index()} ) );
				$quantity_shipped -= $$specs{'txtQuantity'.$Project->ordered_quantity_index()};
			} # end foreach service_id
		} # end foreach ShippingType
		$OP->shipping_type( join(',', sets::intersection( keys %{$services}, map { $_->name() } @ServiceTypes ) ) );

		if ( $quantity_shipped > 0 ) {
			$error .= $quantity_shipped . ' more items need to be shipped or picked up.';	
		} elsif ( $quantity_shipped < 0 ) {
			$error .= $quantity_shipped . ' more items are being shipped or picked up than are being ordered.';	
		} # end if
	} # end if

	if ( $param{'requested_for'.$project_index.'_year'} and $param{'requested_for'.$project_index.'_month'} and $param{'requested_for'.$project_index.'_day'} ) {

		if ( ! Date::Calc::check_date( map { 1*$param{join('','requested_for',$project_index,'_',$_)} } ( 'year','month','day' ) ) ) {
			return q{Date is not valid. Please select a correct date.};
		} # end if
		$OP->requested_for( sprintf('%.4d-%.2d-%.2d', map { @param{'requested_for'.$project_index.'_'.$_} } ( 'year','month','day' ) ) );
	} # end if

	$error .= $Project->save({reference=>$param{"Reference$project_index"}} ) if $param{"Reference$project_index"} and ($param{"Reference$project_index"} ne $Project->reference());
	if ( ref $OP eq 'openprint::OrderedProject' ) {
		$Project->price( $OP->quantity_index(), undef );
$openprint::log->debug('Project price ' . $Project->price( $OP->quantity_index() ) );
		$OP->price( undef );
$openprint::log->debug('OProject price ' . $OP->price() );
		$OP->quantity( $Project->quantity( $OP->quantity_index(), undef ) );
	} elsif ( ref $OP eq 'openprint::OrderedProduct' ) {
	#$OP->price( $Project->price( $OP->quantity_index(), undef ) );
	#$OP->quantity( $Project->quantity( $OP->quantity_index(), undef ) );
	} else {
		$log->error('Unknown type of Ordered item!');
	} # end if
	$error .= $OP->save();
	return $error;
} # end foreach save_project_information

# comes here on the transition from orde_info to orde_info_cred_card or order_info_digi_cheq
# stores the order information into the database
sub store_order_info {
	my $order_id = $param{order_id};
	$order_id = get_unfinished_order( ) if ! $order_id;

	my %required_fields = map { $_ => $_ } split(',', $openprint::config{OrderRequiredFields});
	my $error = '';
	$error .= 'Company Name is a required field.<br/>' if $required_fields{company_name} and ($param{company_name} eq '');
	$error .= 'Address is a required field.<br/>' if $required_fields{address1} and ($param{address1} eq '');
	$error .= 'City is a required field.<br/>' if $required_fields{city} and ($param{city} eq '');
	$error .= 'State/Province is a required field.<br/>' if $required_fields{state} and ($param{state} eq '');
	$error .= 'PostalCode is a required field.<br/>' if $required_fields{postalcode} and ($param{postalcode} eq '');
	$error .= 'Country is a required field.<br/>' if $required_fields{country} and ($param{country} eq '');
	$error .= 'Email is a required field.<br/>' if $required_fields{email} and ($param{email} eq '');
	$error .= 'Purchase Order is a required field.<br/>' if $required_fields{po} and ($param{po} eq '');

	if ( exists $param{company_id} and ! $param{company_id} ) {
		my @Companies = openprint::Company->find( 'name lc' => lc $param{company_name} );
		if ( @Companies == 1 ) {
			$param{company_id} = $Companies[0]->id();
		} else {
			$error .= 'Please select a company.<br/>';
		} 
	} # end if

	$_ = Email::Valid->address($param{email});
	if ( ( ! $_ ) or ( $_ ne $param{email} ) ) {
		$error .= 'Email is not a valid email address.<br>';
	} # end if

	if ( $error ) {
		return $error;
	} # end if

	if ( ! $param{user_id} ) {
		my @Users = openprint::User->find( email => $param{email} );
		if ( @Users == 1 ) {
			$param{user_id} = $Users[0]->id();
		} elsif ( $param{company_id} and ! @Users ) {
			my $User = new openprint::User();
			$error .= $User->save({
				email	=>	$param{email},
				firstname	=>	$param{firstname},
				lastname	=>	$param{lastname},
				phone		=>	$param{phone},
				company_id	=>	$param{company_id},
			});
		}
	} # end if

	my $Order = new openprint::Order( $order_id );
	if ( $param{company_id} ) {
		$Order->company_id( $param{company_id} );
		$session{company_id} = $param{company_id};
	} # end if
	$Order->po($param{po});
	$Order->currency_id( openprint::Currency::get_current()->id() );
	$error .= $Order->save(\%param);
	return $error;
} # end sub store_order_info

sub get_invoice_to {
	my ( $variable, $Order ) = @_;

	@$variable{
		'company_name',
		'salutation',
		'firstname',
		'lastname',
		'address1',
		'address2',
		'city',
		'state',
		'country',
		'postalcode',
		'phone',
		'fax',
		'email'
	} = $Order->get('company_name','salutation','firstname','lastname','address1','address2','city','state','country','postalcode','phone','fax','email');

} # end sub get_invoice_to

sub get_misc {
	my ( $variable, $Order ) = @_;

	$log->debug("********* START OF Get Misc **************");
	$$variable{Order} = $Order;

	@$variable{'Downpayment','TOTAL', 'CreationDate', 'ORDER_STATUS', 'CurrencyIndex', 'PONUM','AdministratorComments','AdministratorName'} = $Order->get('downpayment','total','created_on','status','currency_id','po','administrator_comments','administrator_name');


	if ( $Order->status() ne 'Cancelled' ) {
		$$variable{AmountOutstanding} = Math::Round::nearest( 0.01, $Order->total() - $Order->paid() );
		$$variable{DepositDue} = Math::Round::nearest( 0.01, $Order->downpayment() - $Order->paid() ) if $Order->downpayment() and ( $Order->paid() < $Order->downpayment() );
	} # end if

	$$variable{AmountPaid} = Math::Round::nearest( 0.01, $Order->paid() );
} # end sub get_misc

sub display_order {
	my ( $order_id ) = @_;

	my $Order = new openprint::Order( $order_id );
	my $Currency = openprint::Currency::get_current();
	@variable{'CurrencyName','CurrencySymbol'} = ( $Currency->name(), $Currency->symbol() );
	$variable{Currency} = $Currency;
	$variable{order_id} = $order_id;
	$variable{Order} = $Order;
} # end sub display_order


sub cancel_order {
	my ( $order_id ) = @_;
	my ( $caller, undef, $line ) = caller;
	$log->error("Use of deprecated cancel_order from $caller:$line");
	my $Order = new openprint::Order( $order_id );
	return $Order->cancel();
} # end sub cancel_order


sub fill_user_info {
	my ( $r, $log, $dbh, $variable, $user_index ) = @_;

	if ( $user_index ) {
		my %info;
		my $User = new openprint::User( $user_index );
		@info{'email','title','firstname','lastname','salutation','phone','fax'} = $User->get('email','title','firstname','lastname','salutation','phone','fax');
		my @results;
		foreach my $key ( keys %info ) {
			push @results, "$key~$info{$key}";
		} # end foreach
		return join( '|', @results );
	} # end if
	return;

} # end sub fill_user_info

sub add_to_log {
	my ( $log, $dbh, $order_id, $cust_id, $user_id, $message ) = @_;
	sql::insert( $log, $dbh, 'Order_Log', [
				'Order_Id',	$order_id,
				'Company_Id',	$cust_id ? $cust_id : undef,
				'User_Id',	$user_id,
				'Description',	$message,
				] 
			);
}

sub list_orders {
	my ( $log, $dbh, @orders ) = @_;
	my $html = qq{
<table class="List">
		<tr>
			<th align="left" width="75">Order ID</th>
			<th align="center" width="75">Date</th>
			<th align="center">Ordered By</th>
			<th align="center" width="125">Status</th>
			<th align="right" width="75">Total</th>
			<th align="right" width="100">Balance</th>
		</tr>
	};
	my ( $report_total, $report_balance );
	my $row_class = '';
	foreach my $order_id ( @orders ) {
		my ( $date, $name, $status, $total, $payment, $currency_id ) = sql::execute( $log, $dbh,
				q{SELECT	to_char(dtmOrderDate, 'MM/DD/YYYY'), strFirstName || ' ' || strLastName, (SELECT name FROM Order_Statuses WHERE order_statuses.id = orders.status_id), curTotalSale,(SELECT SUM(amount) FROM Payments WHERE order_id=? AND (deleted=false OR deleted IS NULL) AND completed=true), currency_id FROM Orders WHERE id=?}, $order_id, $order_id );
		$report_total += $total;
		$report_balance += $total-$payment;
		$total = sprintf('%.2f', $total );
		my $balance = sprintf('%.2f', $total-$payment );
		my $Currency = new openprint::Currency( $currency_id );
		my $symbol = $Currency->symbol();

		$html .= qq{
<tr class="$row_class">
			<td><a href="/main/order/history_details.html?order_id=$order_id">&nbsp;$order_id</a></td>
			<td align="center">&nbsp;$date</td>
			<td align="center">&nbsp;$name</td>
			<td align="center">&nbsp;$status</td>
			<td align="right">&nbsp;$symbol $total</td>
			<td align="right">&nbsp;$symbol $balance</td>
		</tr>
		};
		$row_class = $row_class eq '' ? 'colRow' : '';
	} # end foreach $order_id
	$html .= qq{
		<tr class="totals">
			<td colspan="4" align="right"><b>Report Total:</b></td>
			<td align="right">&nbsp;\$ $report_total</td>
			<td align="right">&nbsp;\$ $report_balance</td>
		</tr>
	</table>
};
	return $html;
} # end sub list_orders

1;
__END__
