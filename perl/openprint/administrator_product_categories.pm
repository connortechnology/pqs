use strict;
require openprint::Product_Category;
package openprint::administrator_product_categories;
require openprint;
use vars qw( %variable %session %param %config $log $dbh $r );
*session = \%openprint::session;
*variable = \%openprint::variable;
*param = \%openprint::param;
*log = \$openprint::log;
*dbh = \$openprint::dbh;

sub list {
	my $ProductCategory = new openprint::Product_Category( $param{'category_id'} );
	if ( $param{'btnFunction'} eq 'Save' ) {
		$variable{error} .= $ProductCategory->save( \%param );
		if ( ! $variable{error} ) {
			$variable{ExternalRedirect} = '/administrator/product_categories/list.html';
			$session{information} .= 'Category saved.';
		} # end if
	} elsif ( $param{'btnFunction'} eq 'Delete' ) {
		$variable{error} .= $ProductCategory->delete();
		if ( ! $variable{error} ) {
			$variable{ExternalRedirect} = '/administrator/product_categories/list.html';
		} # end if
	} elsif ( $param{'btnFunction'} eq 'Export' ) {
	    my @header = ( 'Name', 'Description' );
	    my @data = sql::execute( $log, $dbh, 'SELECT name, description FROM Product_Categories' );
    	misc::export_csv( $r, $log, \%variable, 'Product_Categories.csv', \@header, \@data );
	} # end if
} # end sub list

sub edit {
	my $ProductCategory = new openprint::Product_Category( $param{'category_id'} );
	if ( $param{'btnFunction'} eq 'Copy' ) {
		$ProductCategory = $ProductCategory->copy();
		$ProductCategory->save();
	} elsif ( $param{'btnFunction'} eq 'Export' ) {
	    my @header = ( 'Name', 'Description' );
	    my @data = map { @$_{'name','description'} } openprint::Product_Category->find();
    	misc::export_csv( $r, $log, \%variable, 'Product_Categories.csv', \@header, \@data );
	} elsif ( $param{'btnFunction'} eq 'Import' ) {
		my $error = '';
		if ( $param{'fileImport'} ) {
			my $upload = $r->upload( 'fileImport' );
			my $io = $upload->io();
			$_ = <$io>;

			my $csv = Text::CSV_XS->new();
			my %categories = map { $_->name(), $_ } openprint::Product_Category->find();

			my $ac = sql::start_transaction( $dbh );
			while ( <$io> ) {
				my $status = $csv->parse($_);
				my ( $name, $description ) = misc::trim( $csv->fields() );
				next if ! $name;
				if ( ! $categories{$name} ) {
					$categories{$name} = new openprint::Product_Category();
				} # end if
				$categories{$name}->name( $name );
				$categories{$name}->description( $description );
				$error .= $categories{$name}->save();
			} # end while
			sql::end_transaction( $dbh, $ac );
		} else {
			$log->warn( "No file given to upload." );
		} # end if
		if ( $error ne '' ) {
			return misc::error( $log, $dbh, \%variable, 'Import errors.', $error );
		} # end if
	} # end if
	$variable{Category} = $ProductCategory;
} # end sub edit

1;
__END__
