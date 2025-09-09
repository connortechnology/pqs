use strict;
package openprint::MaterialSpecification;
our @ISA = qw( openprint::Object );
require openprint;
require openprint::Material;
require ssi;

use vars qw( $debug $table $serial %fields %transforms %defaults );
$debug = 0;
$table = 'Material_Specifications';
$serial = 'materialspecification_id_seq';

%fields = (
	id	    	  	=>	'id',
	material_id 	=>	'material_id',
	equipment_id	=>	'equipment_id',
	min		      	=>	'min',
	max		      	=>	'max',
	units	      	=>	'units',
	name			    =>	'name',
	value			    =>	'value',
	interpolate	  =>	'interpolate',
);

%transforms = (
	id				=>	[ 's/\D//g','<2147483647' ],
);
%defaults = (
	equipment_id	=>	undef,
	min				=>	undef,
	max				=>	undef,
	value			=>	undef,
	interpolate		=>	1,
);

sub Material {
  return new openprint::Material($_[0]{material_id});
}

sub get_units {
  my $self = shift;
  my $field = shift;

  my $config;
  my $material = $self->Material();

  if ($material->servicetype_id()) {
    my $module = $material->ServiceType()->type();
    if (!$module) {
      $openprint::log->error("No service type set for ".$material->name());
    } else {
      $module =~ s/^openprint::Estimating:://;
      $module = 'openprint::Estimating::'.$module;
      eval ( 'require '.$module.';' );
      $openprint::log->error("eval error $@") if $@;

      if (my $function = $module->can('MaterialSpecificationsConfiguration')) {
        $config = $function->($$material{name});
      } else {
        $openprint::log->debug("No function $module => MaterialSpecificationsConfiguration");
      }
      $openprint::log->debug("Config for $$material{name} ->$field ".Data::Dumper::Dumper($config));
    }
  } else {
    $openprint::log->debug("No servicetype_id for $$material{name}");
  }

  $config = $$config{$$self{name}} if $config;
  my $field_name = 'spec_'.$field.'-'.$$self{id};

  my $value = lc $self->$field();
  $openprint::log->debug("value: $value for $field $$config{$field}");

  if (!($config and $$config{$field})) {
    return ssi::input( type=>'text', name=>$field_name, value=>$value );
  }
  if (!@{$$config{$field}}) {
    return '';
  } elsif (@{$$config{$field}}==1) {
    return ssi::input( type=>'hidden', name=>$field_name, value=>$$config{$field}[0] ).$$config{$field}[0];
  }
  my @values = map { $_, $_ } @{$$config{$field}};
  if ($value and !sets::isin($value, $$config{$field})) {
    push @values, $value, 'Invalid value '.$value;
  }
  if ((!defined $value) and sets::isin('', $$config{$field})) {
    $value = '';
  }
  if (!sets::isin('', $$config{$field})) {
    unshift @values, '', 'no units set';
  }
  return ssi::select( \@values, $value, { name=>$field_name } )
}

1;
__END__
