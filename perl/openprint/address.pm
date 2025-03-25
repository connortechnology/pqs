package openprint::address;

use strict;

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
		); # end %fields

sub new {
	my ( $parent, $log, $dbh, $index, $company_id ) = @_;
	my $self = {};
	bless $self;
	$self->{log} = $log;
	$self->{dbh} = $dbh;

	if ( $index ) {
		$self->{index} = $index;
	} else {
		$_ = "SELECT nextval('Address_Index_seq')";
		( $self->{index} ) = sql::execute( $log, $dbh, $_ );
		sql::insert( $self->{log}, $self->{dbh}, 'tbl_Addresses', 'lngIndex', $self->{index}, 'company_id', $company_id );
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
		@$values{@get_fields} = sql::execute( $self->{log}, $self->{dbh}, $_ );
	} # end if

	return @$values{@requested_fields};
} # end sub get

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

	if ( @set_fields ) {
		sql::update( $self->{log}, $self->{dbh}, 'tbl_Addresses', 'lngIndex = '.$self->{index}, @set_fields );
	} # end if

} # end sub get

sub delete {
	my $self = shift;
	sql::execute( undef, undef, 'DELETE FROM tbl_Addresses WHERE lngIndex = '.$self->{index} );
} # end sub delete

1;

__END__

