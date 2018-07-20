package eprint::address;

use strict;

my %form_fields = (
		'txtShippingCompanyName'    =>  'CompanyName',
		'txtShippingContact'      	=>  'FirstName',
		'txtShippingFirstName'      =>  'FirstName',
		'txtShippingLastName'       =>  'LastName',
		'rdbShippingSalutation'     =>  'Salutation',
		'txtShippingAddress1'       =>  'Address1',
		'txtShippingAddress2'       =>  'Address2',
		'txtShippingCity'           =>  'City',
		'ddmShippingStateProvince'  =>  'StateProvince',
		'ddmShippingCountry'        =>  'Country',
		'txtShippingPostalCode'     =>  'PostalCode',
		'txtShippingPhone'          =>  'Phone',
		'txtShippingExtension'      =>  'Extension',
		'txtShippingFax'            =>  'Fax',
		'txtShippingEmail'          =>  'Email',
		'txtShippingCubicle'        =>  'Cubicle',
		'txtShippingInstructions'   =>  'Instructions',
		'txtShippingLocationName'    				=>  'shipname',
);

my %fields = (
		'CompanyName'   =>  'strCompanyName', 
		'FirstName'     =>  'strFirstName', 
		'LastName'      =>  'strLastName', 
		'Salutation'	=>	'strSalutation',
		'Address1'      =>  'strAddress1', 
		'Address2'      =>  'strAddress2', 
		'City'          =>  'strCity', 
		'StateProvince' =>  'strStateProvince', 
		'PostalCode'    =>  'strPostalCode', 
		'Country'       =>  'strCountry', 
		'Phone'         =>  'strPhone', 
		'Extension'     =>  'strExtension', 
		'Fax'           =>  'strFax',
		'Email'			=>	'strEmail',
		'Cubicle'		=>	'strCubicle',
		'Instructions'		=>	'Instructions',
		'shipname'		=>	'shipname',
		); # end %fields

sub new {
	my ( $parent, $log, $dbh, $index ) = @_;
	my $self = {};
	bless $self;
	$self->{log} = $log;
	$self->{dbh} = $dbh;

	if ( $index ) {
		$self->{index} = $index;
	} else {
		$_ = "SELECT nextval('Address_Index_seq')";
		( $self->{index} ) = sql::sql_statement( $log, $dbh, $_ );
		sql::insert( $self->{log}, $self->{dbh}, 'tbl_Addresses', 'lngIndex', $self->{index} );
	} # end if
	return $self;
} # end sub new

sub get {
	my $self = shift;
	my @requested_fields = @_;

	my @get_fields = ();
	my $values = $self->{values};

	foreach my $field ( @requested_fields ) {
		if ( defined $fields{$field} ) {
			if ( defined $self->{values}->{$field} ) { 
				# means we have already loaded the value for this one
			} else {	
				# need to load it	
				push @get_fields, $field;
			} # end if	
		} else {
			$self->{log}->warn("Address::Get::Invalid field requested: ($field)." );
		} # end if
	} # end foreach	

	# Load in the needed fields
	if ( @get_fields ) {
		$_ = "SELECT " . join( ',',@fields{@get_fields}) . " FROM tbl_Addresses WHERE lngIndex = '" . $self->{index} . "'";
		@$values{@get_fields} = sql::sql_statement( $self->{log}, $self->{dbh}, $_ );
	} # end if

	return @$values{@requested_fields};
} # end sub get

sub as_string {
	my $self  = shift;

	my @add = $self->{dbh}->selectrow_array(q{
		SELECT * FROM tbl_addresses WHERE lngindex = ?
	}, undef, $self->{index});
	shift @add;
	return join(' ', @add);

}

sub bake_form_hash {
	my $self  = shift;
	my $hash  = shift;
	my $format  = shift;
	

	print STDERR "START BAKE  \n";
	return unless $self->{index};

	my $data  = $self->{dbh}->selectrow_hashref(q{
		SELECT * FROM tbl_addresses WHERE lngindex = ?
	}, {}, $self->{index} ); 

	my $rev = {};

	map { $rev->{$form_fields{$_}} = $_ } keys %form_fields;

	map {
		my $key = $rev->{$_};

	  	$key =~ s/Shipping// if $format;

		my $fname = lc($fields{$_}); 
		  
		$hash->{$key} = $data->{$fname};

	} keys %fields;


}


sub form_fields {
	return \%form_fields;
}

sub form_set {
	my ( $self, $form ) = @_;

    my %params;


    foreach my $field ( keys %form_fields ) {

		print STDERR "GET PARAM: $field \n";
    	#$params{$form_fields{$field}} = misc::trim($form->{$field}) if defined $form->{$field};
    	$params{$form_fields{$field}} = $form->{$field} if defined $form->{$field};
    }

	use Data::Dumper;
	print STDERR "FORM SET PARAMS ", Dumper(\%params, $form);
	$self->set(\%params);

}


# if we have previously loaded info for this product, and it hasn't changed, that field will not be saved.
# If we have not previously loaded the info, we will just save it whether it has actually changed or not.
# We do this for efficiency's sake.  
sub set {
	my ( $self, $params ) = @_;
	my @set_fields = ();
	my $values = $self->{values};

	foreach my $field ( keys %{$params} ) {
		if ( $field eq 'PostalCode' ) {
			$params->{$field} =~ tr/[a-z]/[A-Z]/;
		} # end if
		if ( defined $fields{$field} ) {
			# if valid db field
			if ( ! defined $values->{$field} or $values->{$field} ne $params->{$field} ) {
				# Only make changes to fields that have changed
				$values->{$field} = $params->{$field};	# update cache
				push @set_fields, $fields{$field}, $params->{$field};	#mark for sql updating
			} # end if
		} else {
			$self->{log}->warn("Address::Set::Invalid field requested: ($field)." );
		} # end if
	} # end foreach
	my $up = $self->{dbh}->selectrow_array(q{
		SELECT lngindex FROM tbl_addresses where lngindex = ?
	}, undef, $self->{index});

	if ( @set_fields ) {
		if ( $up ) {
			sql::update( $self->{log}, $self->{dbh}, 'tbl_Addresses', 'lngIndex = '.$self->{index}, @set_fields );
		} else {
			sql::insert( $self->{log}, $self->{dbh}, 'tbl_Addresses', @set_fields );
		}
	} # end if

} # end sub get

sub delete {
	my $self = shift;
	sql::sql_statement( $self->{log}, $self->{dbh}, 'DELETE FROM tbl_Addresses WHERE lngIndex = '.$self->{index} );
	sql::sql_statement( $self->{log}, $self->{dbh}, 'DELETE FROM ship_address  WHERE shipid   = '.$self->{index} );
} # end sub delete

1;

__END__

