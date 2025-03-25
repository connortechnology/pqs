use strict;
package openprint::JMF_Message;
our @ISA = qw(openprint::Object);
require openprint::Object;
require openprint::logs;


my $debug = 0;

my $table = 'JMF_Messages';

my %fields = (
	'id'			=>	'id',
	'equipment_id'	=>	'equipment_id',
	'created_on'			=>	'created_on',
	'comment'		=>	'comment',
);

sub find {
	my %params = @_;
	my @values;
	my $sql = q{SELECT * FROM JMF_Messages WHERE 1>0};
	if ( $params{'equipment_id'} ) {
		$sql .= ' AND equipment_id=?';
		push @values, $params{'equipment_id'};
	} # end if
	if ( $params{'Equipment'} ) {
		$sql .= ' AND equipment_id=?';
		push @values, $params{'Equipment'}->id();
	} # end if
	if ( $params{'category_id'} ) {
		$sql .= ' AND category_id=?';
		push @values, $params{'category_id'};
	} # end if
 if ( $params{'created_on_start'} and $params{'created_on_end'} ) {
        $sql .= q{ AND (created_on BETWEEN ? AND ?)};
        push @values, @params{'created_on_start','created_on_end'};
    } elsif ( $params{'created_on_start'} ) {
        $sql .= q{ AND (created_on >= ?)};
        push @values, $params{'created_on_start'};
    } elsif ( $params{'created_on_end'} ) {
        $sql .= q{ AND (created_on <= ?)};
        push @values, $params{'created_on_end'};
    } # end if

	$sql .= " ORDER BY $params{'order'}" if $params{'order'};
	$sql .= " LIMIT $params{'limit'}" if $params{'limit'};
	my $data = $openprint::dbh->selectall_arrayref( $sql, {Slice=>{}}, @values );
	if ( ! $data ) {
		$openprint::log->error("Error loading JMF_Messages: ($sql) (@values)");
		return;
	} elsif ( $debug ) {
		$openprint::log->error("DEBUG loading JMF_Messages: ($sql) (@values)");
	} # end if
	return map { new openprint::JMF_Message( $_->{id}, $_ ); } @$data;
} # end sub find

sub load {
	my ( $self, $data ) = @_;
	if ( ! $data ) {
		$data = $openprint::dbh->selectrow_hashref( 'SELECT * FROM JMF_Messages WHERE id=?', {}, $$self{'id'} );
	} # end if
	@$self{keys %fields} = @$data{keys %fields};
} # end sub load

sub save {
	my $self = shift;

	my $ac = sql::start_transaction( $openprint::dbh );
	my %sql;
	foreach my $key ( keys %fields ) {
		$sql{$key} = $$self{$key};
	} # end foreach

	if ( ! $$self{'id'} ) {
		if ( ! ( @$self{'id'} = sql::execute( $openprint::log, $openprint::dbh, q{SELECT nextval('JMF_Message_Id_seq')} ) ) ) {
			sql::end_transaction( $openprint::dbh, $ac );
			return 'Error allocating new JMF Message<br/>';
		} # end if
		$sql{'id'} = $$self{'id'};
		if ( $_ = sql::insert( $openprint::log, $openprint::dbh, $table, \%sql ) ) {
			sql::end_transaction( $openprint::dbh, $ac );
			return "Error inserting JMF Message : $_<br>";
		} # end if
	} else {
		if ( $_ = sql::update( $openprint::log, $openprint::dbh, $table, ['id=?', $$self{'id'}], \%sql ) ) {
			sql::end_transaction( $openprint::dbh, $ac );
			return "Error updating JMF MEssage : $_<br>";
		} # end if
	} # end if
	sql::end_transaction( $openprint::dbh, $ac );
	$self->load();
} # end sub save

sub delete {
	my $self = shift;

	my $ac = sql::start_transaction( $openprint::dbh );
	sql::execute( $openprint::log, $openprint::dbh, q{DELETE FROM JMF_Messages WHERE id=?}, $$self{'id'} );
	sql::end_transaction( $openprint::dbh, $ac );
} # end sub delete

sub Equipment {
	my $self = shift;
	if ( @_ ) {
		$$self{'equipment_id'} = (shift)->id();
	} # end if
	return new openprint::Equipment( $$self{'equipment_id'} );
}

1;
__END__
