use strict;
package openprint::PageFlip;
our @ISA = qw( openprint::Object );

require openprint::PageFlip_Page;

use vars qw( $debug $table $serial %fields %defaults %transforms );
$debug = 0;
$table = 'pageflip';
$serial = 'pageflip_id_seq';

%fields = (
	'id'	=>	'id',
	'docket'	=>	'docket',
	'company_id'	=>	'company_id',
	'page_files'	=>	'page_files',
	'created_on'	=>	'created_on',
	'updated_on'	=>	'updated_on',
);

sub Pages {
	my ( $self, %params ) = @_;

	if ( %params ) {
		$params{'pageflip_id'} = $$self{'id'};
		return openprint::PageFlip_Page->find(%params);
	} # end if
	if ( ! $$self{'Pages'} ) {
		@{$$self{'Pages'}} = openprint::PageFlip_Page->find('pageflip_id'=>$$self{'id'}, 'order'=>'page');
	} # end if
	return @{$$self{'Pages'}};
} # end sub Pages

1;
__END__
