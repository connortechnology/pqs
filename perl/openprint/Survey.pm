use strict;
package openprint::Survey;
our @ISA = qw( openprint::Object );

require sql;
require openprint::usergroup;
require openprint::Survey_Question;
require openprint::Survey_Response;

use vars qw( $debug $table $serial %fields %transforms %defaults );
$debug = 0;
$table = 'Surveys';
$serial = 'survey_id_seq';

%fields = (
	'id'			=>	'id',
	'name'			=>	'name',
	'description'	=>	'description',
	'created_on'	=>	'created_on',
	'created_by'	=>	'created_by',
);
%transforms = (
    'name' => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
    'description' => [ 's/^\s+//m', 's/\s+$//m', 's/\s\s+/ /mg' ],
);
%defaults = (
	'id'		=>	undef,
	'created_on'	=>	q`'NOW()'`,
	'created_by'	=>	q`$session{user_id}`,
);

sub delete {
	my $self = shift;
	my $error;
	my $ac = sql::start_transaction($openprint::dbh);
	sql::execute( undef, undef, q{DELETE FROM Survey_Responses WHERE survey_id=?}, $$self{id} );
	foreach my $Q ( $self->Questions() ) {
		foreach my $A ( $Q->Available_Answers() ) {
			$error .= $A->delete();
		} # end foreach
		$error .= $Q->delete();
	} # end foreach Question
	sql::execute( undef, undef, q{DELETE FROM Surveys WHERE id=?}, $$self{id} );
	sql::end_transaction( $openprint::dbh, $ac );
	return $error;
} # end sub delete

sub next {
	my $self = shift;
	return new openprint::Survey( sql::execute( undef, undef, q{SELECT MIN(id) FROM Surveys WHERE id > ?}, $$self{id} ) );
} # end sub next;

sub previous {
	my $self = shift;
	return new openprint::Survey( sql::execute( undef, undef, q{SELECT MIN(id) FROM Surveys WHERE id > ?}, $$self{id} ) );
} # end sub previous

sub Questions {
    my $self = shift;
    if ( ! $$self{Questions} ) {
        @{$$self{Questions}} = openprint::Survey_Question->find('survey_id'=>$$self{id},'order'=>'sorting,id');
    } # end if
    return @{$$self{Questions}};
} # end sub Questions

sub Responses {
    my $self = shift;
    if ( ! $$self{Responses} ) {
        @{$$self{Responses}} = openprint::Survey_Response->find('survey_id'=>$$self{id});
    } # end if
    return @{$$self{Responses}};
} # end sub Responses

sub copy {
    my $self = shift;
    my $new = new openprint::Survey();
    $$new{name} = 'Copy of ' . $$self{name};
    $$new{description} = $$self{description};
	my $ac = sql::start_transaction( $openprint::dbh );
    $new->save();
    foreach my $Q ( $self->Questions() ) {
        my $Q2 = $Q->copy();
        $Q2->survey_id($new->id());
		last if	$Q2->save();
        push @{$$new{Questions}}, $Q2;
		foreach my $Available_Answer ( $Q->Available_Answers() ) {
			my $new_Available_Answer = $Available_Answer->copy();
			#$new_Available_Answer->question_id( $Q2->id() );
			last if $new_Available_Answer->save({'question_id'=>$Q2->id()});
		} # end foreach 
    } # end foreach
	sql::end_transaction( $openprint::dbh, $ac );
    return $new;
} # end sub copy

sub can_edit {
	return 0 if ! $openprint::session{'user_id'};
	return 1 if ! $_[0]{'id'};
	return 1 if $openprint::session{'user_type'} eq 'A';
	return 1 if ( $openprint::session{'user_id'} == $_[0]{'created_by'} );
	return 1 if openprint::usergroup::is_user_in( ['Quality Control'], $openprint::session{user_id} );
	return 0;
} # end sub can_edit

1;
__END__
