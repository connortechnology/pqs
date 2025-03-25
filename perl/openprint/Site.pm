use strict;
package openprint::Site;
our @ISA = qw( openprint::Object );
require openprint::Object;
require openprint::Host_Site;

use vars qw( $debug $table $serial %fields %transforms %defaults );

$debug = 0;
$table = 'sites';
$serial = 'sites_id_seq';

%fields = (
	id	        =>	'id',
	company_id	=>	'company_id',
	name      	=>	'name',
  created_on  => 'created_on',
  updated_on  => 'updated_on',
  deleted     => 'deleted',
);
%transforms = (
	name							=>	[ 's/[\.\,]//g', 's/^\s+//', 's/\s+$//','s/\///g' ],
);
%defaults = (
	created_on			=>	q`'NOW()'`,
	updated_on			=>	q`'NOW()'`,
  deleted         =>  0,
);

sub Company {
  my $self = shift;
  if (!$$self{Company}) {
    $$self{Company} = new openprint::Company($$self{company_id});
  }
  return $$self{Company};
}
sub Owner {
  return $_[0]->Company();
}

sub Host_Sites {
  my $self = shift;
  if (@_) {
    $$self{Host_Sites} = shift;
  }
  if (!$$self{Host_Sites}) {
    if ($$self{id}) {
      $$self{Host_Sites} = [ openprint::Host_Site->find(site_id=>$$self{id}) ];
    } else {
      $$self{Host_Sites} = [];
    }
  }
  return @{$$self{Host_Sites}} if wantarray;
  return $$self{Host_Sites};
}

sub Hosts {
  my $self = shift;
  $$self{Hosts} = shift if @_;
  if (!$$self{Hosts}) {
    if ($$self{id}) {
      my @host_ids = map { $$_{host_id} } $self->Host_Sites();
      $$self{Hosts} = [@host_ids ? openprint::Host->find(id=>\@host_ids) : ()];
    } else {
      $$self{Hosts} = [];
    }
  }
  return @{$$self{Hosts}} if wantarray;
  return $$self{Hosts};
}

sub link_to {
  my $self = shift;
  my $text = shift if @_;
  $text = ssi::html_escape($$self{name}) if !$text;
  my $options = shift if @_;
	return sprintf('<a href="/sites/view.html?site_id=%d"%s>%s</a>', $$self{id}, ($options?join(' ', map {$_.'="'.$$options{$_}.'"'} keys %$options):''), $text );
}

1;
__END__
