use strict;
require openprint::Asset;
require openprint::Object;
require openprint::Object_Type;

package openprint::Object_Asset;
our @ISA = qw(openprint::Object);
use vars qw( $debug %fields %find_fields %transforms %defaults $table @identified_by );
$debug = 0;
$table = 'object_assets';
@identified_by = ( 'object_id','object_type_id','asset_id' );
%fields = (
	object_id			=>	'object_id',
	object_type_id	=>	'object_type_id',
	object_type		=>	undef,
	asset_id			=>	'asset_id',
);
%find_fields = (
	object_type	=>	'(SELECT name FROM object_types WHERE id=object_type_id)',
);

sub Asset {
	return new openprint::Asset( $_[0]{'asset_id'} );
} # end sub Asset

sub upload {
	my $error = '';
	my $Asset = openprint::Asset::upload( $_[1], $_[2] );
	if ( ref $Asset eq 'openprint::Asset' ) {
		my $Photo = openprint::Object_Asset->find_one(asset_id=>$$Asset{id},object_id=>$_[0]{id},object_type=>ref $_[0]);
		if ( ! $Photo ) {
			$Photo = new openprint::Object_Asset();
			$error .= $Photo->save({ asset_id=>$$Asset{id}, object_id=>$_[0]{id},object_type=>ref $_[0]});
			#$error .= new openprint::Log()->save({'action'=>'Upload Photo', 'Object'=>$Photo});
		} else {
			$error .= 'Asset already exists for this object.';
		} # end if
	} else {
		$error .= "Failed to upload asset: $Asset";
	} # end if
	return $error;
} # end sub upload

1;
__END__
