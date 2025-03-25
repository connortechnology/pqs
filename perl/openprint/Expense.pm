require openprint::Object;
require openprint::Expense_Tax;
require openprint::Expense_Account;
require Math::Round;
use strict;

package openprint::Expense_Category;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %transforms %defaults );
$debug = 0;
$table = 'expense_categories';
$serial = 'expense_categories_id_seq';
%fields = (
	id	  =>	'id',
	name	=>	'name',
);
%transforms = (
  name => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);
%defaults = (
);

package openprint::Expense;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %find_fields %transforms %defaults );

$debug = 1;
$table = 'expenses';
$serial = 'expenses_id_seq';

%fields = (
	id			      	=>	'id',
	owner_id		  	=>	'owner_id',
	recipient_id  	=>	'recipient_id',
  recipient       =>  undef,
	category_id	  	=>	'category_id',
	category		  	=>	undef,
	account_id	  	=>	'account_id',
	account		    	=>	undef,
	description	  	=>	'description',
	amount		    	=>	'amount',
	amount_locked		=>	'amount_locked',
	total			    	=>	'total',
	total_locked		=>	'total_locked',
	created_on	  	=>	'created_on',
	due_on		    	=>	'due_on',
	paid_on		    	=>	'paid_on',
	invoiced_on	  	=>	'invoiced_on',
	currency_id	  	=>	'currency_id',
	business_use		=>	'business_use',
	business_use_amount		=>	'business_use_amount',
	attention	  		=>	'attention',
	deleted		  		=>	'deleted',
	transaction_id	=>	'transaction_id',
);

%find_fields  = (
  recipient =>  '(SELECT name FROM companies WHERE companies.id=recipient_id)',
  category =>  '(SELECT name FROM Expense_Categories WHERE expense_categories.id=category_id)',
);

%transforms = (
	id			      	=>	[ 's/\D//g' ],
	owner_id		  	=>	[ 's/\D//g' ],
	currency_id	  	=>	[ 's/\D//g' ],
	recipient_id		=>	[ 's/\D//g' ],
	amount			    =>	[ 's/[^\d\.\-]//g' ],
	total			    	=>	[ 's/[^\d\.\-]//g' ],
	business_use		=>	[ 's/[^\d\.\-]//g' ],
  description	  	=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);

%defaults = (
	due_on	    	=>	q`'NOW()'`,
	invoiced_on 	=>	q`'NOW()'`,
	created_on  	=>	q`'NOW()'`,
	recipient_id	=>	undef,
	business_use	=>	undef,
	paid_on	    	=>	undef,
	amount_locked	=>	0,
	total_locked	=>	0,
	account_id  	=>	undef,
	category_id 	=>	undef,
	attention	  	=>	0,
	deleted		  	=>	0,
	amount		  	=>	undef,
	total		    	=>	undef,
);


sub link_to {
	return sprintf('<a href="/employee/accounting/expense.html?expense_id=%d">%s</a>', $_[0]{id}, 'Expense ' . $_[0]{id} );
}
sub Company {
	return new openprint::Company( $_[0]{owner_id} );
} # end sub Company

sub Currency {
  return $openprint::Currency if !$_[0]{currency_id};
	return new openprint::Currency( $_[0]{currency_id} );
} # end sub Currency

sub recipient {
  my $self = shift;
  if ( @_ ) {
    $$self{recipient} = openprint::Company->transform(name=>shift);
    if ( $$self{recipient} ) {
      my @Companies = openprint::Company->find('name lc'=> lc $$self{recipient});
      if ( ! @Companies ) {
        my $Company = new openprint::Company();
        $Company->save({name=>$$self{recipient}});
        $$self{recipient_id} = $$Company{id};
      } elsif ( @Companies == 1 ) {
        $$self{recipient_id} = $Companies[0]{id};
      } else {
        $openprint::log->error("Error setting recipient due to many companies matching");
      }
    }
  } # end if setting

  if ( (!$$self{recipient}) and $$self{recipient_id} ) {
    my $Company = new openprint::Company($$self{recipient_id});
    $$self{recipient} = $$Company{name};
  }
  return $$self{recipient} ? $$self{recipient} : '';
}

sub category_id {
	if ( @_ > 1 and defined $_[1] ) {
		$_[0]{category_id} = $_[1];
    $_[0]->Category(undef);
	} # end if
	return $_[0]{category_id};
} # end sub category_id

sub category {
  my $self = shift;
	if ( @_ ) {
    $$self{category} = openprint::Expense_Category->transform(name=>shift);
    if ( $$self{category} ) {
      my $Category = openprint::Expense_Category->find_one('name lc'=>lc $$self{category});
      if ( ! $Category ) {
        $Category = new openprint::Expense_Category();
        $Category->save({name=>$$self{category}})
      } # end if	
      $$self{category_id} = $Category->id();
      $$self{Category} = $Category;
      return $Category->name();
    }
	} # end if
  return $self->Category()->name();
} # end sub category

sub Category {
  my $self = shift;
  $$self{Category} = shift if @_;
  if ( ! $$self{Category} ) {
    if ($$self{category_id}) {
      $$self{Category} = new openprint::Expense_Category($$self{category_id});
    } else {
      $$self{Category} = new openprint::Expense_Category();
    }
  }
  return $$self{Category};
} # end sub Category

sub account {
	if ( @_ > 1 ) {
		my $Account = openprint::Expense_Account->find_one('name lc'=>lc $_[1]);
		if ( ! $Account ) {
			$Account = new openprint::Expense_Account();
			$Account->save({'name'=>$_[1]})
		} # end if	
		$_[0]{account_id} = $Account->id();
		return $Account->name();
	} # end if
	return new openprint::Expense_Account( $_[0]{account_id} )->name();
} # end sub account

sub Account {
	return new openprint::Expense_Account( $_[0]{account_id} );
} # end sub Account

sub Recipient {
	return new openprint::Company( $_[0]{recipient_id} );
}

sub destroy {
  my $self = shift;
  if (!$$self{id}) {
    $openprint::log->error("Attempt to delete Expense without id");
    return;
  }
	foreach my $T ( $self->Taxes() ) {
		$T->destroy();
	} # end foreach
	$self->SUPER::destroy();
} # end sub destroy

sub Taxes {
  my $self = shift;

  $$self{Taxes} = shift if @_;

  if ( $$self{id} ) {
    $$self{Taxes} = [openprint::Expense_Tax->find(expense_id=>$$self{id})] if !$$self{Taxes};
  }
 
  if ( ! $$self{Taxes} ) {
    $$self{Taxes} = [];
  } # end if

  if ( (!@{$$self{Taxes}}) and ($$self{invoiced_on} or $$self{paid_on}) ) {
    my $country = $self->Recipient()->country() ? $self->Recipient()->country()  : $self->Company()->country();
    return @{$$self{Taxes}} if ! $country;
    my $state = $self->Recipient()->state() ? $self->Recipient()->state()  : $self->Company()->state();

    foreach my $Tax ( openprint::Tax->find(
        'period_start null_or_<='   =>  ( $$self{invoiced_on} ? $$self{invoiced_on} : $$self{paid_on} ),
        'period_end null_or_>='     =>  ( $$self{invoiced_on} ? $$self{invoiced_on} : $$self{paid_on} ),
        country   =>  $country,
        ( $state ? (state => $state) : ()),
      ) ) {
        my $T = new openprint::Expense_Tax();
        $T->set({
            Expense     =>  $self,
            expense_id	=>	$$self{id},
            tax_id      =>  $$Tax{id},
          rate        =>  $$Tax{rate},
        });
      $openprint::log->debug("New aTax: " . $T->to_string()) if $debug;
      # Should not save.  Saving will be done in the save function This is okay, because in the html, we id our field by the tax_id
      #$T->save({ 'expense_id'=>  $$self{id}}) if $$self{id};
      push @{$$self{Taxes}}, $T;
    } # end foreach Tax
    #} else {
    #$openprint::log->debug('Not loading taxes: ' . (scalar @{$$self{Taxes}}) . ' country: ' . $self->Company()->country() . ' state: ' . $self->Company()->state() . ' invoiced_on: ' . ($$self{invoiced_on}?$$self{invoiced_on}:'never'));
  } # end if
  return @{$$self{Taxes}};
} # end sub Taxes

sub save {
	my $self = shift;

	$self->set( @_ );

	if ( $self->id() ) {
		# Taxes, get current, get relevant, save, delete as appropriate
		my @Old_Taxes = $self->Taxes();
		my @New_Taxes;

		foreach my $Tax ( openprint::Tax->find(
					'period_start null_or_<='   =>  $$self{invoiced_on},
					'period_end null_or_>='     =>  $$self{invoiced_on},
					country   =>  $self->Company()->country(),
					state     =>  $self->Company()->state()),
				) {
			my $T = $self->Tax( $Tax );
			push @New_Taxes, $T;
			if ( $T->id() ) {
				for ( my $i = 0; $i < @Old_Taxes; $i += 1 ) {
					if ( $Old_Taxes[$i]->id() == $T->id() ) {
						splice @Old_Taxes, $i, 1;
						last;
					} # end if
				} # end for
			} # end if
		} # end foreach Tax
		foreach my $Tax ( @Old_Taxes ) {
			$Tax->delete() if $Tax->id();
		} # end foreach Tax
		@{$$self{Taxes}} = @New_Taxes;
	} # end if
	foreach my $Tax ( $self->Taxes() ) {
		$Tax->amount(undef);
	} # end foreach Tax
	$self->total(undef);
	my $error = $self->SUPER::save( @_ );
	if ( ! $error ) {
		foreach my $Tax ( $self->Taxes() ) {
			$error .= $Tax->save({expense_id=>$self->id()});
		} # end foreach Tax
	} # end if
	return $error;
} # end sub save

sub total {
	if ( @_ == 2 ) {
		$_[0]{total} = $_[1];
	} # end if
	if ( ! $_[0]{total} ) {
    $_[0]{total} = $_[0]{amount};
    if ( defined($_[0]{total}) ) {
      foreach my $Tax ( $_[0]->Taxes() ) {
        $_[0]{total} += $Tax->amount();
      } # end foreach Tax
      $_[0]{total} = $_[0]{total} ? Math::Round::nearest(0.01, $_[0]{total}) : '0.00';
    }
	} # end if
	return $_[0]{total};
} # end sub total

sub Tax {
	foreach my $T ( $_[0]->Taxes() ) {
		return $T if $$T{tax_id} == $_[1]->id();
	} # end foreach
  my $result = openprint::Expense_Tax->find_one(expense_id=>$_[0]{id}, tax_id=>$_[1]->id() ) if $_[0]{id};
  if ( ! $result ) {
    $result = new openprint::Expense_Tax();
    $result->set({
        expense_id  => $_[0]{id},
        tax_id      => $_[1]->id(),
        rate        => $_[1]->rate(),
      });
  } # end if
  return $result;
} # end sub Tax

sub tax_charged { 
  my ( $self, $name, $yesno ) = @_;
	foreach my $T ( $self->Taxes() ) {
    my $tax_name = $T->Tax()->name();
    if ( $tax_name eq $name ) {
      if ( @_ > 2 ) {
        $$T{charge} = $yesno;
        $T->amount(undef);
        $openprint::log->debug("Setting tax charged to $yesno for T: " . $T->to_string()) if $debug;
      }
      return $T->charge();
    }
  } # end foreach Tax
  $openprint::log->error("Tax not found for $name in " . $self->to_string());
}

sub business_use_amount {
	if ( @_ > 1 ) {
		$_[0]{business_use_amount} = $_[1];
	} # end if
	if ( ! defined $_[0]{business_use_amount} ) {
		$_[0]{business_use_amount} = $_[0]->amount() ? Math::Round::nearest( 0.01, $_[0]{amount} * ( $_[0]{business_use} / 100 ) ) : '0.00';
	} # end if
	return $_[0]{business_use_amount};
} # end sub business_use_amount

sub to_string {
  my $self = shift;
  my $type = ref($self);
  #return $type . ': '. join(' ' , map { $$self{$_} ? $_.' => '.(ref $$self{$_} eq 'ARRAY' ? join(',', @{$$self{$_}}) : $$self{$_} ) : () } keys %fields ).
  return 'Expense: ' . $self->Company()->name() . ' ' . $self->account(). ' to ' . $self->recipient(). ' '.$$self{category_id}.':'.$self->category().' '.$self->Currency()->format($self->total()).
 ($$self{business_use} ? ' ' . $$self{business_use}. '% business = ' . $self->business_use_amount() : '').
  "\nTaxes:".join("\n", map { $_->to_string() } $self->Taxes());
}

sub amount {
  my $self = shift;
  if ( !defined $$self{amount} ) {
    if ( defined $$self{total} ) {
      $openprint::log->debug('Getting amount from total');
      my $amount = $$self{total};
      foreach my $Tax ( $self->Taxes() ) {
        $amount -= $Tax->amount();
      }
      $$self{amount} = $amount;
    }
  }
  return $$self{amount};
}

sub recipient_id {
  my $self = shift;
  if (@_) {
    $$self{recipient_id} = shift;
    $self->recipient(undef);
  }
  return $$self{recipient_id};
}
1;
__END__
