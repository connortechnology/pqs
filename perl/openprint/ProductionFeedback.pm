use strict;
require openprint::Project;
require openprint::Equipment;
require openprint::Project_Service;

package openprint::ProductionFeedback;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %find_fields %transforms %defaults );

$debug = 0;
$table = 'ProductionFeedback';
$serial = 'ProductionFeedback_id_seq';
%fields = (
	'id'			=>	'id',
	'project_id'	=>	'project_id',
	'service_id'	=>	'service_id',
	'starting_on'	=>	'starting_on',
	'ending_on'		=>	'ending_on',
	'user_id'		=>	'user_id',
	'comment'		=>	'comment',
	'version'		=>	'version',
	'signature_id'	=>	'signature_id',
	'equipment_id'	=>	'equipment_id',
	'quantity'		=>	'quantity',
);
%find_fields = (
	'company_id'	=>	'(SELECT companyindex FROM tbl_Projects WHERE index=project_id)',
	'signature'		=>	'(SELECT image_data FROM signaturecapture WHERE signaturecapture.id=signature_id)',
);
%defaults = (
	'user_id'		=>	undef,
	'service_id'	=>	undef,
	'signature_id'	=>	undef,
	'equipment_id'	=>	undef,
	'starting_on'	=>	'NOW()',
	'ending_on'		=>	'NOW()',
	'quantity'		=>	undef,
);
%transforms = (
	'equipment_id'	=>	[ 's/\D//g' ],
	'project_id'	=>	[ 's/\D//g' ],
	'service_id'	=>	[ 's/\D//g' ],
	'user_id'		=>	[ 's/\D//g' ],
	'signature_id'	=>	[ 's/\D//g' ],
	'quantity'		=>	[ 's/[^\-\.\d]//g' ],
);

sub User {
  require openprint::User;
	return new openprint::User( $_[0]{'user_id'} );
} # end sub User

sub Signature {
  require openprint::SignatureCapture;
	return new openprint::SignatureCapture( $_[0]{signature_id} );
} # end sub Signature

sub Project {
	return new openprint::Project( $_[0]{project_id} );
} # end sub Project

sub Equipment {
	return new openprint::Equipment( $_[0]{equipment_id} );
} # end sub Equipment

sub Service {
    if ( $_[0]{project_id} and $_[0]{service_id} ) {
    return new openprint::Project_Service( { project_id=>$_[0]{project_id}, service_id=>$_[0]{service_id} } );
    } else {
    return new openprint::Project_Service();
    } # end if
} # end sub Service

1;
__END__
