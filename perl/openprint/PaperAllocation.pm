use strict;
package openprint::PaperAllocation;
our @ISA = qw(openprint::Object);

use openprint ();
use vars qw($debug %session $dbh $log $table $serial %fields %find_fields %transforms %defaults );
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*session = \%openprint::session;

require sql;
require ssi;
require misc;
require openprint::Skid;
require openprint::User;

$debug = 0;

$table = 'paper_allocations';
$serial = 'paper_allocation_id_seq';

%fields = (
	id				=>	'id',
	paper_id		=>	'paper_id',
	operator_id		=>	'operator_id',
	created_on		=>	'created_on',
	units			=>	'units',
	quantity		=>	'quantity',
	skid_ids		=>	'skid_ids',
	condition_id	=>	'condition_id',
	docket			=>	'docket',
);
%find_fields = (
	project_id	=>	'(SELECT id FROM Projects WHERE lngdocketnumber=docket)',
	order_id	=>	'(SELECT id FROM Orders WHERE docket=paper_allocations.docket)',
	company_id	=>	'(SELECT company_id FROM orders WHERE docket=paper_allocations.docket)',
);

%transforms = (
	id			=>	[ 's/\D//g', '<2147483647' ],
	paper_id			=>	[ 's/\D//g', '<2147483647' ],
	operator_id			=>	[ 's/\D//g', '<2147483647' ],
	condition_id			=>	[ 's/\D//g', '<2147483647' ],
	quantity	=>	[ 's/\D//g' ],
);

%defaults = (
	quantity		=>	undef,
	created_on		=>	q`'NOW()'`,
	condition_id	=>	undef,
);

sub delete {
	if ( $_[0]{id} ) {
		my $ac = sql::start_transaction( );
		if ( $_[0]->docket() ) {
      my $Order = $_[0]->Order();
      if ($Order->id()) {
        $Order->add_log( 'Allocation deleted.' . ( @_ > 1 ? ' Reason: ' . $_[1] : '' ) );
      }
		} # end if
		$_ = $_[0]->SUPER::delete();
		if ( $_ ) {
			$dbh->rollback();
			sql::end_transaction( undef, $ac );
			return;
		}
		my $Paper = $_[0]->Paper();
		$Paper->allocated(undef,undef);
		$Paper->available(undef);
		$Paper->save();
		sql::end_transaction( undef, $ac );
		return;
	} else {
		return 'already deleted.';
	} # end if
} # end sub delete

sub Condition {
require openprint::InventoryCondition;
	if ( $_[0]{condition_id} ) {
		return new openprint::InventoryCondition( $_[0]{condition_id} );
	} elsif ( $_[0]{skid_ids} and ( @{$_[0]{skid_ids}} == 1 ) ) {
		my @Skids = $_[0]->Skids();
		my $Skid = $Skids[0];
		if ( $Skid and $Skid->id() ) {
		my $C = $Skid->Content( $_[0]->Paper() );
			if ( $C ) {
				return $C->Condition();
			} # end if
		} # end if
	} # end if
	return new openprint::InventoryCondition();
} # end sub Condition

sub Paper {
	return new openprint::Paper( $_[0]{paper_id} );
} # end sub Paper
sub Stock {
	return new openprint::Paper( $_[0]{paper_id} );
} # end sub Paper
sub Skids {
	if ( ! $_[0]{Skids} ) {
		if ( $_[0]{skid_ids} and @{$_[0]{skid_ids}} ) {
			$_[0]{Skids} = [ openprint::Skid->find( id=> $_[0]{skid_ids} ) ];
		} else {
			$_[0]{Skids} = [];
		} # end if
	} # end if
	return @{$_[0]{Skids}};
} # end sub Skids

sub User {
	return new openprint::User( $_[0]{operator_id} );
} # end sub User
sub Project {
require openprint::Project;
$openprint::log->error("PaperAllocation::Project deprecated");
	return openprint::Project->find( docket=>$_[0]{docket} );
} # end sub Project

sub Order {
require openprint::Order;
	my $Order = openprint::Order->find_one(docket=>$_[0]{docket}) if $_[0]{docket};
	$Order = new openprint::Order() if ! $Order;
	return $Order;
} # end sub Order

sub old_Skids {
	my @old_skids;
    foreach my $Skid ( $_[0]->Skids() ) {
        if ( $Skid->last_seen_days() > 30 ) {
            push @old_skids, $Skid;
        } # end if
    } # end foreach Skid
	return @old_skids;
} # end sub old_Skids

sub send_notification {
	my ( $self ) = @_;

	my %info;
	$info{Allocation} = $self;
	my $Order = $info{Order} = $self->Order();
	my $Paper = $info{Paper} = $self->Paper();
	my @old_skids = @{$info{OldSkids}} = $self->old_Skids();

	my @recipients = map { $_->notification('Stock Allocations') eq 'Yes' ? $_ : () } openprint::User->find( company_id=>$openprint::config{owner_id}, 'usergroup any'=>'InventoryManager' );

  my $offsite = 0;
	my $nolocation = 0;
	foreach my $Project ( $Order->Projects() ) {
		foreach my $sig_id ( $Project->signatures() ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $sig_id );
			my $Press;
			if ( $$sig_specs{UsePress} ) {
				$Press = openprint::Equipment->find_one(strid=>$$sig_specs{UsePress});
			} else {
				$Press = openprint::Equipment->find_one(strid=>$$sig_specs{'ddmPress'.$Project->ordered_quantity_index()});
			} # endif
			if ( $Press ) {
				foreach my $Skid ( $self->Skids() ) {
					if ( ! $Skid->location_id() ) {
						$nolocation = 1;
					} elsif ( $Skid->Location()->Root()->id() != $Press->Location()->Root()->id() ) {
						$offsite = 1;
					} # end if
				} # end foreach PA
			} # end if
		} # end foreach sig
	} # end foreach Project
	$info{offsite} = $offsite;
	$info{nolocation} = $nolocation;

	push @recipients, $Order->Company()->CSR() if $offsite or $nolocation or @old_skids;
	if ( $Paper->available() < 0 ) {
		my @PAs = openprint::PaperAllocation->find( paper_id=>$Paper->id());
		@recipients = map { new openprint::User( $_ ) } sets::exclude( [ $session{user_id} ], [ sets::union( (map { $_->Order()->Company()->salesrep_id() } @PAs), (map{$_->id()}@recipients) ) ] );
	} # endif

	$info{ReplacementText} = ssi::include( '/email_content/stock_allocation_notification.html', \%info );
require openprint::Email;
	my $Email = new openprint::Email();
	$Email->html_body( ssi::include( '/email_template.html', \%info ) );
	$Email->send( 
			TO			=>	\@recipients, 
			FROM		=>	$openprint::User,
			SUBJECT =>	'Stock allocated for docket ' . $Order->docket(),
			);

} # end sub stock_allocation_notification

sub link_to {
    return sprintf('<a href="/employee/inventory/allocation.html?allocation_id=%1$d">%2$s</a>', $_[0]{id}, @_ > 1 ? $_[1] : $_[0]->quantity().$_[0]->units() . ' of ' . $_[0]->Paper()->to_string() );
} # end sub link_to

sub can_delete {
	if ( $openprint::session{user_type} eq 'A' ) {
		return 1;
	}
	if ( $openprint::session{user_id} == $_[0]{operator_id} ) {
		return 1;
	}
	my $Order = $_[0]->Order();
	if ( sets::isin( $$Order{salesrep_id}, [ $openrpint::User{id}, $openprint::User->assistant_ids(), $openprint::User->csr_ids() ] ) ) {
		return 1;
	}
	my $Company = $Order->Company();
	if ( sets::isin( $$Company{salesrep_id}, [ $$openprint::User{id}, $openprint::User->assistant_ids(), $openprint::User->csr_ids() ] ) ) {
		return 1;
	} # end if
}

1;
__END__
