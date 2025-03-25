package openprint::Task;
@ISA = qw( openprint::Object );
require openprint::Object;
require openprint::Department;
require openprint::Task_Action;
require openprint::Task_Type;
use strict;
use warnings;

use vars qw( $debug $table $serial %fields %transforms %defaults );
$debug = 1;
$table = 'tasks';
$serial = 'tasks_id_seq';
%fields = map { $_ => $_ } qw(
   id
    department_id
    action_id
    title
    notes
    rb_id
    owner_id
    deadline
    type_id
    ntf_2
    created_on
    createdby_id
    updated_on
    updatedby_id
    ch_1
    ch_2
    ch_3
    ch_4
    ch_5
    ch_6
    ch_7
    ch_8
    ch_9
    ch_10
    ch_11
    ch_12
    ch_13
    ch_14
);
%transforms = (
);
%defaults = (
	created_on	=>	q`'NOW()'`,
	updated_on	=>	q`'NOW()'`,
);

sub Owner {
  my $self = shift;
  $$self{Owner} = shift if @_;
  if ( !$$self{Owner}) {
    $$self{Owner} = openprint::Company->find_one(id=>$$self{owner_id}) if $$self{owner_id};
    $$self{Owner} = new openprint::Company() if ! $$self{Owner};
  }
  return $$self{Owner};
}

sub Department {
my $self = shift;
$$self{Department} = shift if @_;
if (!defined($$self{Department})) {
  $$self{Department} = new openprint::Department($$self{department_id});
}
return $$self{Department};
}
sub department {
my $self = shift;
$$self{department} = shift if @_;
  if (! defined $$self{department}) {
    $$self{department} = $self->Department()->name();
  }
  return $$self{department};
}
sub Action {
my $self = shift;
$$self{Action} = shift if @_;
if (!defined($$self{Action})) {
  $$self{Action} = new openprint::Task_Action($$self{action_id});
 }
 return $$self{Action};
}

sub action {
  my $self = shift;
  $$self{action} = shift if @_;
  if (! defined $$self{action}) {
    $$self{action} = $self->Action()->name();
  }
  return $$self{action};
}

sub assigned_to {
my $self = shift;
my $user = new openprint::User($$self{owner_id});
return $user->name();
}
sub Type {
my $self = shift;
$$self{Type} = shift if @_;
if (!defined($$self{Type})) {
  $$self{Type} = new openprint::Task_Type($$self{type_id});
 }
 return $$self{Type};
}
sub type {
  my $self = shift;
  $$self{type} = shift if @_;
  if (! defined $$self{type}) {
    $$self{type} = $self->Type()->name();
  }
  return $$self{type};
}

sub UpdatedBy {
  my $self = shift;
  $$self{UpdatedBy} = shift if @_;
  $$self{UpdatedBy} = new openprint::User($$self{updatedby_id}) if !$$self{UpdatedBy};
}

sub CreatedBy {
  my $self = shift;
  $$self{CreatedBy} = shift if @_;
  $$self{CreatedBy} = new openprint::User($$self{createdby_id}) if !$$self{CreatedBy};
}
sub Company {
  my $self = shift;
  $$self{Company} = shift if @_;
  if (!$$self{Company}) {
    $$self{Company} = $$self{rb_id} ? openprint::Company->find_one({accountnumber=>$$self{rb_id}}) : new openprint::Company();
  }
  return $$self{Company};
}

sub company_id {
  return $_[0]->Company()->id();
}

1;
__END__
