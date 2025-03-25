use strict;
package openprint::Test_Result;
our @ISA = qw(openprint::Object);
require openprint::Test_Result_Result;
require openprint::Test;

use vars qw( $table $serial %fields %transforms %defaults );
$table = 'test_results';
$serial = 'test_results_id_seq';

%fields = ( 
	id		=>	'id',
	employee_id	=>	'employee_id',
	rma_id	=>	'rma_id',
	technician_id	=>	'technician_id',
	rdate			=>	'rdate',
	tested_on		=>	'tested_on',
	result			=>	undef,
	result_id		=>	'result_id',
	remarks			=>	'remarks',	
	problem_level	=>	'problem_level',
	cost			=>	'cost',
	test_id			=>	'test_id',
	test			=>	undef,
);
%transforms = (
	remarks => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);
%defaults = (
	tested_on	=>	q`'NOW()'`,
	technician_id	=>	q`$session{user_id}`,
	rdate		=>	q`'NOW()'`,
	cost		=>	undef,
);

sub Technician {
	return new openprint::User( $_[0]{technician_id} );
} # end sub Technician

sub Result {
    return new openprint::Test_Result_Result( $_[0]{result_id} );
} # end sub Result

sub result {
    if ( @_ > 1 ) {
        my $Result = openprint::Test_Result_Result->find_one('name lc'=> lc $_[1] );
        if ( ! $Result ) {
            $Result = new openprint::Test_Result_Result();
            $Result->save({'name'=>$_[1]});
        } # end if
        $_[0]{'result_id'} = $Result->id();
        $_[0]{'result'} = $Result->name();
    }
    if ( ! $_[0]{'result'} ) {
        $_[0]{'result'} = new openprint::Test_Result_Result( $_[0]{'result_id'} )->name();
    } # end if
    return $_[0]{'result'};
} # end sub result

sub Test {
    return new openprint::Test( $_[0]{test_id} );
} # end sub Test

sub test {
    if ( @_ > 1 ) {
        my $Test = openprint::Test->find_one('name lc'=> lc $_[1] );
        if ( ! $Test ) {
            $Test = new openprint::Test();
            $Test->save({name=>$_[1]});
        } # end if
        $_[0]{test_id} = $Test->id();
        $_[0]{test} = $Test->name();
    }
    if ( ! $_[0]{test} ) {
        $_[0]{test} = new openprint::Test( $_[0]{test_id} )->name();
    } # end if
    return $_[0]{test};
} # end sub test

1;
__END__
1;
__END__
