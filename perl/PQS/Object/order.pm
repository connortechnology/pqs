package PQS::Object::order; 

use strict; 
use warnings; 
use session; 

use Data::Dumper;


sub new {
    my ($class,$id) = @_;
    
    my $self = { 
        log => session::log,
        dbh => session::dbh,
    };

    bless $self, $class;

    if ($id) {
        $self->{id} = $id;
        $self->load();
        $self->{list} = 1;
    }

    return $self;
}


sub load {

	my $self = shift;

 	$self->{specs} = PQS::model::order::get_order($self->{id});

}

sub status {
	my $self = shift;

	return $self->{specs}{strstatus};

}
sub payment_total {
	my $self = shift;

	return PQS::model::order::payments($self->{id}) || 0;
}

sub deposit_required {
	my $self = shift;

	return PQS::model::order::downpayment($self->{id});

}

sub pending_deposit {
	my $self = shift;


	my $p =  $self->payment_total;

	my $dp =  $self->deposit_required;

	print STDERR "HAVE Payments: $p Depost Required: $dp \n";

	if ( $self->payment_total < $self->deposit_required ) {
		return 1
	}

	return 0;

	
	#return $self->status eq $status::order->{PD} ? 1 : 0;

}
sub projects {
	my $self = shift;

	my $list = PQS::model::order::get_projects($self->{id});

	return @{$list};

}

sub status_tree {
	my $self = shift;

	map {
		my $p = new PQS::Object::project($_);
		$p->update_status();
	} $self->projects;

	return $self->update_status();
	

}

sub update_status {

	my $self = shift;

	my $status;

	#IF peding deposit then go no futher
	if (  $self->pending_deposit ) {
		$status = 'PD';
		PQS::model::order::set_status($self->{id}, $status::order->{$status});
		return $self->status;
	}


	if ( PQS::model::order::waiting_for_files($self->{id}) ) {
		$status = 'WF';
		PQS::model::order::set_status($self->{id}, $status::order->{$status});
		return $status::order->{$status};
	}

	if ( PQS::model::order::project_status($self->{id}, $status::order->{'IP'} ) ) {
		$status = 'IP';
		PQS::model::order::set_status($self->{id}, $status::order->{$status});
		return $status::order->{$status}
	}

	$status = 'CP';

	PQS::model::order::set_status($self->{id}, $status::order->{$status});

	return $status::order->{$status}



}


sub order_id {
	my $self = shift;
	return PQS::model::order::get_order_by_pid($self->{id});

}





1;
