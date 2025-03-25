package openprint::Expense_Rule;
our @ISA = qw(openprint::Object);

require JSON;

use vars qw( $debug $table $serial %fields %transforms %defaults );
$debug = 0;
$table = 'expense_rules';
$serial = 'expense_rules_id_seq';
%fields = (
  id          =>  'id',
  name        =>  'name',
  rules_json  =>  'rules_json',
  action_json =>  'action_json',
  created_on  =>  'created_on',
  updated_on  =>  'updated_on',
  category_id =>  'category_id',
);
%transforms = (
  name => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);
%defaults = (
  created_on  =>  'NOW()',
  updated_on  =>  'NOW()',
  category_id =>  undef,
);

sub deleted {
  return 0;
}

sub action { 
  my $self = shift;

  $$self{action} = JSON::decode_json($$self{action_json});
  return $$self{action};
}

sub rules {
  my $self = shift;

  my $rules = JSON::decode_json($$self{rules_json});
  if ( ref $rules ne 'ARRAY' ) {
    $rules = [ $rules ];
  }
  $$self{rules} = $rules;
  return @{$$self{rules}};
}

sub match {
  my ( $self, $line ) = @_;
  foreach my $rule ( $self->rules() ) {
    foreach my $key ( keys %{$rule} ) {
      #$openprint::log->debug("rule: $key $$rule{$key}");
      my @matches;
      if ( $$rule{$key} =~ /^\/(.*)\/\w*$/ ) {
        if ( $$line{$key} ) {
          @matches = $$line{$key} =~ /$1/i;
          #$openprint::log->debug("testing $key $$line{$key} =~ $$rule{$key} @matches $?");
          if ( @matches ) {
            #$openprint::log->debug("Have matches ".%+);
            foreach my $p ( keys %+ ) {
              $$self{matches}{$p} = $+{$p};
              $openprint::log->debug("Have matches $p => " . $$self{matches}{$p});
            }
            return scalar @matches;
          }
        }  # end if $$line{key}
      } else {
        $openprint::log->error("Unknown test $key $$rule{$key}");
      } # end if rule type
    } # end foreach key
  } # end foreach rule
  return 0;
} # end sub match

sub apply {
  my ( $self, $Expense ) = @_;

  my %action = %{$self->action()};

  foreach my $key ( keys %action ) {

    if ( $key =~ /^(\w+):(\w+)$/ ) {
      $openprint::log->debug("Complex action $key Expense->$1($2, $action{$key})");
      $Expense->$1($2, $action{$key});
    } elsif ( $action{$key} =~ /\$/ ) {
      $Expense->$key(eval $action{$key});
      $openprint::log->error("Failure to eval $action{$key} $@") if $@;
    } else {
      if ( ref $action{$key} eq 'ARRAY' ) {
        $Expense->$key(@{$action{$key}});
      } else {
        $Expense->$key($action{$key});
      }
    }
    $openprint::log->debug("Applied action $$self{id} $key $action{$key}, result: ".(defined($$Expense{$key})?$$Expense{$key}:'undef')."\n".$Expense->to_string());
  } # end foreach key
} # end sub apply

sub category {
  if ( @_ > 1 ) {
    my $Category = openprint::Expense_Rule_Category->find_one('name lc'=>lc openprint::Expense_Rule_Category->transform('name',$_[1]));
    if ( ! $Category ) {
      $Category = new openprint::Expense_Rule_Category();
      $Category->save({name=>$_[1]});
    } # end if
    $_[0]{category_id} = $Category->id();
    $_[0]{category} = $Category->name();
  } elsif ( ( ! defined $_[0]{category} ) and $_[0]{category_id} ) {
    $_[0]{category} = $_[0]->Category()->name();
  } # end if
  return $_[0]{category};
} # end sub category

sub Category {
  return new openprint::Expense_Rule_Category( $_[0]{category_id} );
} # end sub Category

1;
__END__
