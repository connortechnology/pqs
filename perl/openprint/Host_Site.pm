use strict;
package openprint::Host_Site;
our @ISA = qw( openprint::Object );
require openprint::Object;
require openprint::Host;
require openprint::Site;

use vars qw( $debug $table $serial %fields %transforms %defaults );

$debug = 0;
$table = 'hosts_sites';
$serial = 'hosts_sites_id_seq';

%fields = (
	id	        =>	'id',
	host_id	=>	'host_id',
	site_id	=>	'site_id',
);
%transforms = (
);
%defaults = (
);

sub Host {
  my $self = shift;
  if (!$$self{Host}) {
    $$self{Host} = new openprint::Host($$self{host_id});
  } 
  return $$self{Host};
}

sub Site {
  my $self = shift;
  if (!$$self{Site} ) {
    $$self{Site} = new openprint::Site($$self{site_id});
  }
  return $$self{Site};
}

1;
__END__
