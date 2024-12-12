use strict;
package openprint::Object_Type;
our @ISA = qw( openprint::Object );

use vars qw( $debug $table %fields %transforms %defaults $serial $default_sort );

$debug = 0;
$table = 'object_types';
$serial = 'object_types_id_seq';
$default_sort	=	'lower(name)';
%fields = (
	id		=>	'id',
	name	=>	'name',
	human	=>	'human',
);
%defaults = (
);
%transforms = (
  name  => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
  human => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g', 's/^openprint:://' ],
);

sub Object {
	if ( $_[0]{name} ) {
    my $name = $_[0]{name};
    $name =~ s/::/\//g;
    eval {
      require $name.'.pm';
    };
		$openprint::log->error("failed requiring $name $@") if $@;
  	return $_[0]{name}->new($_[1]);
	}
	my ($caller, undef, $line) = caller;
	$openprint::log->error("Unknown object from $caller:$line");
	return new openprint::Object();
} # end sub Object

sub human {
	if ( @_ > 1 ) {
		$_[0]{human} = $_[1];
	}
	if ( ! $_[0]{human} ) {
		$_[0]{human} = $_[0]{name};
		$_[0]{human} =~ s/^openprint:://;
	}
	return $_[0]{human};
}

1;
__END__
