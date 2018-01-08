package eprint::customer_credit;

use strict;

my %fields = (
		'CreditLimit'       =>  'dblCreditLimit',
		'CreditHold'        =>  'ysnCreditHold',
		'Terms'             =>  'lngTerms',
		'Downpayment'		=>	'dblDownpayment',
		);  

my %transforms = (
	'CreditLimit'	=>	's/[^\d\.]//g',
	'Terms'			=>	's/\D//g',
	'Downpayment'	=>	's/[^\d\.]//g',
);

sub new {
	my ( $parent, $log, $dbh, $customer_index, $supplier_index ) = @_;
	my $self = {};
	bless $self;
	$self->{log} = $log;
	$self->{dbh} = $dbh;

	$self->{customer_index} = $customer_index;
	$self->{cust_id} = $customer_index;
	$self->{supplier_index} = $supplier_index;

	$_ = "SELECT lngCustomerIndex FROM tbl_Customer_Credit\n".
		"WHERE lngCustomerIndex = '" . $self->{customer_index} . "'\n";
	#"AND lngSupplierIndex = '" . $self->{supplier_index} . "'\n";
	if ( ! sql::sql_statement( $self->{log}, $self->{dbh}, $_ ) ) {
		sql::insert( $self->{log}, $self->{dbh}, 'tbl_Customer_Credit', 
				'lngCustomerIndex', $self->{customer_index},
	#'lngSupplierIndex', $self->{supplier_index}
				);
	} # end if
	return $self;
} # end sub new

sub get {
	my $self = shift;
	my @requested_fields = @_;

	my @get_fields = ();

	foreach my $field ( @requested_fields ) {
		if ( defined $fields{$field} ) {
			if ( defined $self->{values}->{$field} ) {
				# means we have already loaded the value for this one
			} else {
				# need to load it   
				push @get_fields, $field;
			} # end if  
		} else {
			$self->{log}->warn("Customer_Credit::Get::Invalid field requested: ($field)." );
		} # end if
	} # end foreach 

	# Load in the needed fields
	$self->load_values( @get_fields );
	my $values = $self->{values};
	return @$values{@requested_fields};
} # end sub get

sub load_values {
	my ( $self, @get_fields ) = @_;
	my $values = $self->{values};

	if ( @get_fields ) {
		$_ = "SELECT " . join( ',',@fields{@get_fields}) . " FROM tbl_Customer_Credit\n".
		  "WHERE lngCustomerIndex = '" . $self->{customer_index} . "'\n";
		  #"AND lngSupplierIndex = '" . $self->{supplier_index} . "'\n";
		@$values{@get_fields} = sql::sql_statement( $self->{log}, $self->{dbh}, $_ );
	} # end if

} # end sub load_values

sub set {
	my ( $self, $params ) = @_;
	my @set_fields = ();
	my $values = $self->{values};

	foreach my $field ( keys %{$params} ) {
		if ( defined $fields{$field} ) {
			if ( $transforms{$field} ) {
				eval '$params->{$field} =~ ' . $transforms{$field};
			} # end if
			# if valid db field
			if ( $values->{$field} ne $params->{$field} ) {
				# Only make changes to fields that have changed
				$values->{$field} = $params->{$field};  # update cache
				push @set_fields, $fields{$field}, $params->{$field};   #mark for sql updating
			} # end if
		} else {
			$self->{log}->warn("Customer_Credit::Set::Invalid field requested: ($field)." );
		} # end if
	} # end foreach

	if ( @set_fields ) {
		sql::update( $self->{log}, $self->{dbh}, 'tbl_Customer_Credit', 
			"lngCustomerIndex = '" . $self->{customer_index} . "'\n",
			#"AND lngSupplierIndex = '" . $self->{supplier_index} . "'\n",
			@set_fields );
	} # end if

} # end sub get


sub available {
	my $self = shift;
	my $dbh = session::dbh;

	my $credit_limit    = $self->get('CreditLimit');

    my $debit = $dbh->selectrow_array(q{
        SELECT SUM(curTotalSale)
        FROM tbl_Orders
        WHERE lngCustomerID = ?
        AND strStatus IN
                ('Pending Deposit', 'In Production', 'Complete', 'Paid')
        }, undef, $self->{cust_id}
    );

    my $credit = $dbh->selectrow_array(q{
        SELECT SUM(curAmount)
        FROM tbl_Payments
        WHERE lngCustomerIndex = ?
        }, undef, $self->{cust_id}
    );

	my $avail_credit    = $credit_limit - ( $debit - $credit );

	return $avail_credit;
}

1;

__END__

