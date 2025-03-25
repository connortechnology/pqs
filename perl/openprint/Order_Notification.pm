use strict;
package openprint::Order_Notification;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table %fields %transforms %defaults @identified_by $AUTOLOAD );

$debug = 0;
@identified_by = ( 'order_id', 'user_id' );
$table = 'order_notifications';
%fields = (
    order_id    =>  'order_id',
    user_id 	=>  'user_id',
);
%transforms = (
);
%defaults = (
);

sub User {
	return new openprint::User( $_[0]{user_id} );
} # end sub User

sub AUTOLOAD {
    my $self = shift;
    my $type = ref($self);
    my $name = $AUTOLOAD;
#if ( $self eq 'supplier' ) {
#$openprint::log->debug("Autoload $type $name");
#}
    $name =~ s/.*://;
	if ( $fields{$name} ) {
		if ( @_ ) {
	#$openprint::log->debug("Autoload $type $name $_[0]");
			return $self->{$name} = $_[0];
		} else {
			return $self->{$name};
		} # end if
	} else {
		$self->User()->$name( @_ );
    } # end if
} # end sub AUTOLOAD

1;
__END__
