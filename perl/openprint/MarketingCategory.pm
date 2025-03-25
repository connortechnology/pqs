use strict;
package openprint::MarketingCategory;
our @ISA = qw( openprint::Object );

require sql;

use openprint ();

use vars qw( $debug %fields %find_fields %transforms %defaults $table $serial );
$debug = 0;
%fields = (
	id			=>	'lngindex',
	name			=>	'strname',
	description	=>	'strdescription',
	greeting		=>	'strgreeting',
);
%find_fields = (
	'user_id'		=>	'(SELECT user_id FROM users_in_marketing_categories WHERE category_id=marketing_categories.id)',
	'company_id'	=>	'(SELECT company_id FROM companies_in_marketing_categories WHERE category_id=marketing_categories.id)',
);
$table = 'tbl_marketing_categories';
$serial = 'marketing_categories_index_seq';

sub delete {
	my $self = shift;
	my $ac = sql::start_transaction($openprint::dbh);
	sql::execute( undef, undef, q{DELETE FROM Companies_in_Marketing_Categories WHERE category_id=?}, $$self{id} );
	sql::execute( undef, undef, q{DELETE FROM Users_in_Marketing_Categories WHERE category_id=?}, $$self{id} );
	sql::execute( undef, undef, 'DELETE FROM '.$table.' WHERE '.$fields{id}.'=?', $$self{id} );
	sql::end_transaction( $openprint::dbh, $ac ) if $ac;
} # end sub delete

sub next {
	my $self = shift;
	return new openprint::MarketingCategory( sql::execute( undef, undef, q{SELECT MIN(id) FROM Marketing_Categories WHERE id > ?}, $$self{id} ) );
} # end sub next;
sub previous {
	my $self = shift;
	return new openprint::MarketingCategory( sql::execute( undef, undef, q{SELECT MIN(id) FROM Marketing_Categories WHERE id > ?}, $$self{id} ) );
} # end sub previous

sub Companies {
	my ( $self, %params ) = @_;
	$params{'marketing_category_id any'} = $$self{'id'};
	return openprint::Company->find( %params );
} # end sub Companies

sub companies {
	$openprint::log->warn("Deprecated use of MarketingCategory::companies");
	return Companies(@_);
} # end sub companies

sub add_company {
	my $self = shift;
	if ( @_ == 1 ) {
		my $company = shift;
		if ( ref $company eq 'openprint::Company' ) {
			sql::execute( undef, undef, q{DELETE FROM Companies_In_Marketing_Categories WHERE category_id=? AND company_id=?}, $$self{'id'}, $company->id() );
			sql::insert( undef, undef, 'Companies_In_Marketing_Categories', 'category_id', $$self{'id'}, 'company_id', $company->id() );
		} elsif ( ref $company eq 'ARRAY' ) {
			foreach ( @$company ) { $self->remove_company( $_ ); } # end foreach
		} else {
			# assume that it is a company_id
			sql::execute( undef, undef, q{DELETE FROM Companies_In_Marketing_Categories WHERE category_id=? AND company_id=?}, $$self{'id'}, $company );
			sql::insert( undef, undef, 'Companies_In_Marketing_Categories', 'category_id', $$self{'id'}, 'company_id', $company );
		} # end if
	} elsif ( @_ > 1 ) {
		foreach ( @_ ) { $self->remove_company( $_ ); } # end foreach
	} # end if
} # end sub add_company

sub remove_company {
	my $self = shift;
	if ( @_ == 1 ) {
		my $company = shift;
		if ( ref $company eq 'openprint::Company' ) {
			sql::execute( undef, undef, q{DELETE FROM Companies_In_Marketing_Categories WHERE category_id=? AND company_id=?}, $$self{'id'}, $company->id() );
		} elsif ( ref $company eq 'ARRAY' ) {
			foreach ( @$company ) { $self->remove_company( $_ ); } # end foreach
		} else {
			# assume that it is a company_id
			sql::execute( undef, undef, q{DELETE FROM Companies_In_Marketing_Categories WHERE category_id=? AND company_id=?}, $$self{'id'}, $company );
		} # end if
	} elsif ( @_ > 1 ) {
		foreach ( @_ ) { $self->remove_company( $_ ); } # end foreach
	} # end if
} # end sub remove_company

1;
__END__
