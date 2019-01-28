package eprint::test;

use strict;
use PQS::Object::project;
use session;
use PQS::DB;

use eprint::service;

sub handler {
	
	 my $rec = shift if $ENV{MOD_PERL};

    my $r = Apache2::Request->new($rec);
    $r->parse;

    session::r($r);
	#    session::log($r->log);



    my $dbh      = PQS::DB->connect($r, { AutoCommit => 1 });
    session::dbh($dbh);


	my $dbh = session::dbh;
	my $pids = $dbh->selectcol_arrayref(q{SELECT lngprojectindex from tbl_projects order by 1 desc limit 500});




	print STDERR "START TEST MODULE \n";

	map {
		my $p = new PQS::Object::project($_);
		$p->init_production();

	} @{$pids};


    # read in the data

        # this is where we actually send the page to the client
        $r->content_type('text/html');
        print(  );


	return 1;
}

1;

__END__
