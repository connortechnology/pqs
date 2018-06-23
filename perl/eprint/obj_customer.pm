package eprint::obj_customer;
use strict;
use warnings;

use File::Copy qw(mv);
use File::Path;
use Unicode::Normalize;
use Apache2::RequestUtil;
require eprint::address;

my %fields = (
    # Account Information
    Name                 => 'strCompanyName',
    AccountNumber        => 'strAccountNum',
    AccountActivation    => 'ysnAccountActivation',
    Reseller             => 'ysnReseller',
    Supplier             => 'ysnSupplier',
    SalesPerson          => 'lngSalesPerson',
    NotificationEmail	 => 'notificationemail',
    linescreen	 		 => 'linescreen',

    # Pricing Information
    PriceList            => 'lngPriceList',
    CountyTax            => 'countytax',
    Discount             => 'dblPricingPercent',
    NationalCredit       => 'nationalcredit',
    NationalCreditDefault => 'nationalcreditdefault',
    MailingCredit        => 'mailingcredit',
    MailingCreditDefault => 'mailingcreditdefault',
    OrderCredit       	 => 'ordercredit',
    OrderCreditDefault 	 => 'ordercreditdefault',
    OrderCreditCarry 	 => 'ordercreditcarry',
    TaxExempt1           => 'ysnGSTExempt',
    TaxExempt2           => 'ysnPSTExempt',

    # Service/project display flags.
    PricingServices      => 'ysnpricingservices',
    PricingProjectView   => 'ysnpricingprojectview',
    SeparateStock        => 'ysnseparatestock',
    ProductsOnly         => 'ysnproductsonly',
    PricingQuotes        => 'ysnpricingquotes',

    # Marketing
    CustomGreeting       => 'strCustomGreeting',
    MailingList          => 'ysnMailingList',

    # Contact Information
    Address1             => 'strAddress1',
    Address2             => 'strAddress2',
    City                 => 'strCity',
    StateProvince        => 'strProvState',
    PostalCode           => 'strPostalCodeZip',
    Country              => 'strCountry',
    Phone                => 'strPhone',
    Extension            => 'strExt',
    Fax                  => 'strFax',
    Website              => 'strWebURL',

    # Business Information
    LegalForm            => 'LegalForm',
    LegalBusinessName    => 'strLegalBusName',
    BusinessType         => 'strBusinessType',
    BusinessNature       => 'strBusinessNature',
    BusinessStartDate    => 'dtmBusinessStartDate',
    PresidentOwner       => 'strPresidentOwner',
    Employees            => 'strEmployees',
    AnnualSales          => 'strAnnualSales',
    TaxNumber1           => 'strGSTNumber',
    TaxNumber2           => 'strPSTNumber',
    PrintExpenditure     => 'strPrintExpenditure',

    # Bank Information
    BankName             => 'strBankName',
    BankBranch           => 'strBankBranch',
    BankAccountNumber    => 'strBankAccountNo',
    BankAccountManager   => 'strBankAccountManager',
    BankPhone            => 'strBankPhone',
    BankFax              => 'strBankFax',
    BankEmail            => 'strBankEmail',


    # Shipping
    ShippingAddressIndex => 'lngShippingAddressIndex',

    Warehouse            => 'lngWarehouseID', # ?
    division             => 'division', # ?
);

my %transforms = (
# Change for ECM. Allow zip code as is.
#    PostalCode  =>  [ 'tr/[a-z]/[A-Z]/', 's/[\W]//g' ],
    Discount    =>  [ 's/[^\d\.\-]//g' ],
    TaxNumber1  =>  [ 's/[\D]//g', 's/(\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d).*/$1/' ],
    TaxNumber2  =>  [ 's/[\D]//g', 's/(\d\d\d\d\d\d\d\d\d).*/$1/' ],
);

my %defaults = (
    Discount    => 0,
    SalesPerson => 0,
);

sub new {
    my ($class, $log, $dbh, $id) = @_;
    
    my $self = { 
        log => $log,
        dbh => $dbh,
    };

    bless $self, $class;

    if ($id) {
        $self->{index} = $id;
        $self->get(keys %fields);
    }

    return $self;
}

sub id { shift->{index} }

sub get {
    my $self = shift;
    my @field_names = @_;
    my @needed;

    FIELD:
    foreach my $field ( @field_names ) {
        unless (exists $fields{$field}) {
            warn "Invalid field ($field)";
            next FIELD;
        }

        next if exists $self->{values}{$field}; # Value is already known

        push @needed, $field;
    }
    
    # Get the needed fields from the database.
    $self->_load_values(@needed) if @needed;

    return @{ $self->{values} }{@field_names};
}

sub _load_values {
    my ($self, @needed) = @_;

    my $field_names = join q{, }, @fields{@needed};

    @{ $self->{values} }{@needed} = $self->{dbh}->selectrow_array(qq{
        SELECT $field_names FROM tbl_customer WHERE lngcustomerid = ?
    }, undef, $self->{index});

	$self->{values}{ShippingAdresses} = $self->{dbh}->selectcol_arrayref(q{
		SELECT shipid FROM customer_ship_address WHERE customer = ? ORDER by shipid
	}, undef, $self->{index});

    return scalar @needed;
}

# if we have previously loaded info for this customer, and it hasn't changed, that field will not be saved.
# If we have not previously loaded the info, we will just save it whether it has actually changed or not.
# We do this for efficiency's sake.    
sub set {
    my ($self, $params) = @_;

    my %set_fields;
    my $old_name = $self->{values}{Name};

    FIELD:
    foreach my $field ( keys %{$params} ) {

        unless (defined $fields{$field}) {
            warn "Invalid field name ($field)";
            next FIELD;
        }

        for my $transform ( @{$transforms{$field}} ) {
            eval '$params->{$field} =~ ' . $transform;
        }

        $params->{$field} = $defaults{$field}
            if !defined $params->{$field} && defined $defaults{$field};

        if (  (!defined $self->{values}{$field} && defined $params->{$field}) 
            || $self->{values}{$field} ne $params->{$field} ) 
        {
            # Only make changes to fields that have changed
            $self->{values}{$field}        = $params->{$field}; # Update cache
            $set_fields{ $fields{$field} } = $params->{$field}; # Mark for sql updating
        }
    }

    # Determine path info for where to create customer files.
    my $r    = Apache2::RequestUtil->request;
    my $path = $r->dir_config('site_specific') || $r->document_root.'/site_specific/';
       $path .= '/customers';

    if ( %set_fields ) {
        # Create new customer
        if ( ! $self->{index} ) {
            $self->{index} = $self->{dbh}->selectrow_array(q{
                SELECT nextval('tbl_Customer_lngCustomerID_seq')
            });

            die "Invalid customer ID ($self->{index})" unless $self->{index};

            # Create the new customer.           
            sql::insert($self->{log}, $self->{dbh}, 'tbl_Customer', 
                lngCustomerID   => $self->{index}, 
                dtmDateEntered  => 'NOW',
                dtmLastModified => 'NOW',
                %set_fields 
            );

            my $dir_name = $self->path;

            # Create their customer and project directories.
            unless (-e "$path/$dir_name/projects") {
                mkpath("$path/$dir_name/projects")
                    or die "Couldn't create customer directories: $!";
            }
        } 
        # Edit an existing customer.
        else {
            sql::update($self->{log}, $self->{dbh}, 'tbl_Customer', "lngCustomerID = $self->{index}", 
                dtmLastModified => 'NOW', 
                %set_fields 
            );

            # Rename customer directory if name has changed. TODO locking?
            if (exists $set_fields{strCompanyName}) {
                mv("$path/" . $self->path($old_name), # From
                   "$path/" . $self->path)            # To
                      or die "Moving customer directory failed: $!";
            }
        }
    }
    return 1;
}

# Generate the name of the customer's directory.
sub path {
    my ($self, $name) = @_;

    $name = $self->{values}{Name} unless defined $name;

    # The following list is as permissive as possible, disallowing only the
    # characters invalid in HFS+, FAT32, and Ext2,3. All these file systems
    # allow up to 255 2-btye unicode characters.

    $name = NFKD($name);                 # Normalize Unicode chars.
    $name =~ tr/\x00-\x1F\/\\:*?"<>|/_/; # Reserved characters
    $name =~ s/^ //;                     # Remove leading...
    $name =~ s/ $//;                     #    and trailing spaces
    $name =~ s/(\s)+/$1/;                # Collapse multiple spaces
    $name = substr($name, 0, 240);       # Max 255 chars (2 byte width)

    $name = "$2, $1"
        if $name =~ /^(The\s)(.*)/i; # "The Foo" -> "Foo, The"

    # Group by first character (all non-alpha in 'other' group).
    my $group = lc substr($name, 0, 1);
       $group = '!other' if $group !~ /^[a-z]$/;

    return "$group/" . sprintf("%s (%06d)", $name, $self->{index});
}


sub delete {
    my $self = shift;
    my $id   = $self->{index};

    eprint::inventory::delete_by_customer($self->{log}, $self->{dbh}, $id);

    my $users = $self->{dbh}->selectcol_arrayref("select lnguserid from  tbl_customer_users where lngcustomerid = ?", undef, $id);
    for my $user (@$users) {
      eprint::order::delete_users_orders($self->{log}, $self->{dbh}, $user);
      eprint::quote::delete_users_quotes($self->{log}, $self->{dbh}, $user);
      eprint::print_project::delete_users_projects($self->{log}, $self->{dbh}, $user);
    }
    eprint::order::delete_customers_orders($self->{log}, $self->{dbh}, $id);
    eprint::quote::delete_customers_quotes($self->{log}, $self->{dbh}, $id);
    eprint::print_project::delete_customers_projects($self->{log}, $self->{dbh}, $id);

    $self->{dbh}->begin_work;

    # Remove the customer dir.
    my $r    = Apache2::RequestUtil->request;
    my $path = $r->dir_config('site_specific') || $r->document_root.'/site_specific/';

    rmtree("$path/customers/" . $self->path)
        or die "Can't remove customer directory (" . $self->path . "): $!\n" if (-d "$path/customers/" . $self->path);

    # Remove all record of the customer.
    my @queries = (
        'DELETE FROM tbl_logged_in WHERE lngcustomerid = ?',
        'DELETE FROM tbl_Customer_Users WHERE lngCustomerID = ?',
        'DELETE FROM tbl_Trade_References WHERE lngCustomerId = ?',
        'DELETE FROM tbl_Help_Desk WHERE lngCustomerIndex = ?',
        'DELETE FROM tbl_RMA WHERE lngCustomerIndex = ?',
        'DELETE FROM tbl_Credit_App WHERE lngCustomerIndex = ?',

        # Uhh, yeah. I wish my CC company would do this if I cancelled my card.    
        'DELETE FROM tbl_Customer_Credit WHERE lngCustomerIndex = ?',
    
        'DELETE FROM tbl_Customers_in_Categories WHERE lngCustomerID = ?',
        'DELETE FROM tbl_Customer WHERE lngCustomerID = ?',
    );

    for my $query (@queries) {
        $self->{dbh}->do($query, undef, $id);
    }

    $self->{dbh}->commit;

    return 1;
}

sub get_shipping_address {
    my $self = shift;
	my $id   = shift;

    my $address = eprint::address->new( $self->{log}, $self->{dbh}, $id);

    return $address;
}

sub save_shipping {
    my ($self, $id, $params, $form) = @_;

	$id = undef if $id eq 'New';
    my $address = $self->get_shipping_address($id);


	if ( $form) {
   		$address->form_set( $params );
	} else {
   		$address->set( $params );
	}
	$self->{dbh}->do(qq{INSERT INTO customer_ship_address 
						VALUES ( $self->{index}, $address->{index}) } ) if !$id;
}

sub load_shipping {
    my ($self, @params) = @_;

    if ( ! defined $self->{values}->{'ShippingAddressIndex'} ) {
        $self->_load_values( 'ShippingAddressIndex' );
    }
    my $address = new eprint::address( $self->{log}, $self->{dbh}, $self->{values}->{'ShippingAddressIndex'} );
    return $address->get( @params );
}

sub shipping_hash{

	my $self = shift;
	my $d = $self->{dbh}->selectall_hashref(q{
		SELECT * from tbl_Addresses a, customer_ship_address c WHERE a.lngindex = c.shipid
		AND c.customer = ?
	},'shipid',{},$self->{index});

	return [values %{$d}];

}

sub save_notification {
    my ($self, $title, $address) = @_;

    $_ = "SELECT strAddress FROM tbl_Supplier_Notifications WHERE lngSupplierIndex='".$self->{index}."' AND strTitle='$title'";
    my @results = sql::sql_statement( $self->{log}, $self->{dbh}, $_ );
    if ( @results ) {
        $_ = shift @results;
        if ( $_ ne $address ) {
            sql::update( $self->{log}, $self->{dbh}, 'tbl_Supplier_Notifications', "lngSupplierIndex='".$self->{index}."' AND strTitle='$title'",
                    'strAddress',    $address );
        }
    } 
    else {
        sql::insert($self->{log}, $self->{dbh}, 'tbl_Supplier_Notifications', 
                lngSupplierIndex => $self->{index},
                strTitle         => $title,
                strAddress       => $address,
        );
    }
}

sub load_notification {
    my ($self, $title) = @_;

    return $self->{dbh}->selectrow_array(q{
        SELECT straddress 
        FROM tbl_supplier_notifications 
        WHERE lngsupplierindex = ?
          AND strtitle = ?
    }, undef, $self->{index}, $title);
}

sub next {
    my $self = shift;

    return $self->{dbh}->selectrow_array(q{
        SELECT lngcustomerid 
        FROM tbl_customer 
        WHERE strcompanyname > ( SELECT strcompanyname 
                                 FROM tbl_customer 
                                 WHERE lngcustomerid = ? )
        ORDER BY strcompanyname ASC
        LIMIT 1
    }, undef, $self->{index});
}

sub prev {
    my $self = shift;

    return $self->{dbh}->selectrow_array(q{
        SELECT lngcustomerid 
        FROM tbl_customer 
        WHERE strcompanyname < ( SELECT strcompanyname 
                                 FROM tbl_customer 
                                 WHERE lngcustomerid = ? )
        ORDER BY strcompanyname DESC
        LIMIT 1
    }, undef, $self->{index});
}

1;
