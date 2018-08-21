package eprint::dashboard;

use Apache2::Const qw(:common HTTP_MOVED_TEMPORARILY); # Offers OK, Error, etc for web server.
use strict;

use session;

use Data::Dumper;

use PQS::Object::project;
use DateTime;
use DateTime::Format::Strptime;

our $dbh = session::dbh;

  
sub display {
	my $var = shift;
	my $param = shift;

	my $dbh = session::dbh;
	my $r = session::r;


	my $cols = [
	{ desc=>"Order", 				id=>"lngorderid", 			class=> "srfield", ro=>1 },
	{ desc=>"Project", 				id=>"lngprojectindex", 		class=> "srfield", ro=>1 },
	{ desc=>"Customer", 			id=>"strcompanyname", 		class=> "lgfield", ro=>1 },
	{ desc=>"Contact", 				id=>"contact", 				class=> "rgfield", ro=>1 },
	{ desc=>"Status", 				id=>"status", 				class=> "rgfield", ro=>1 },
	{ desc=>"Project Type", 		id=>"ptype", 				class=> "smfield", ro=>1 },
	{ desc=>"Qty", 					id=>"intquantity1", 		class=> "srfield", ro=>1 },
	{ desc=>"Inks", 				id=>"inks", 				class=> "srfield", ro=>1 },
	{ desc=>"Job Name", 			id=>"strprojectreference",	class=> "lgfield", ro=>1 },
	{ desc=>"Equipment", 			id=>"equipment", 			class=> "srfield", ro=>1 },
	{ desc=>"Finished Size",		id=>"finished", 			class=> "srfield", ro=>1 },
	{ desc=>"Time", 				id=>"time", 				class=> "smfield", ro=>1 },
	{ desc=>"Due Date", 			id=>"duedate", 				class=> "srfield", ro=>1 },
	{ desc=>"Delivery Method", 		id=>"delivery", 			class=> "smfield", ro=>1 },
	{ desc=>"Stock", 				id=>"stock", 				class=> "lgfield", ro=>1 },
	{ desc=>"Sheet Size", 			id=>"sheet_size",			class=> "smfield", ro=>1 },
	{ desc=>"Sheets", 				id=>"sheets", 				class=> "smfield", ro=>1 },
	{ desc=>"P", 					id=>"pulled", 				class=> "tifield", ro=>1 },
	];

	$var->{fields} = $cols;

	my $lines = $dbh->selectall_arrayref( q{
		SELECT *, p.strstatus as status 
		FROM 
			tbl_orders o, tbl_order_contents oc, tbl_projects p, 
			tbl_project_contents pc, tbl_customer c
		WHERE 	o.lngorderid = oc.lngorderid
		AND		oc.lngprojectindex = p.lngprojectindex
		AND		p.lngprojectindex = pc.lngprojectindex
		AND 	p.lngcustomerid = c.lngcustomerid
		AND		strservicetype = 'Printing'
		AND 	o.ysnfinished 
		ORDER by o.lngorderid DESC
		Offset 5
		LIMIT 5 
	}, {Slice => {}} );


	my @data;

	foreach my $l ( @{$lines} ) {

		my $p = new PQS::Object::project($l->{lngprojectindex});

		$l->{ptype} = $p->type_name();

		$l->{inks} = $p->ink_sum($l->{lngserviceindex});

		$l->{finished} = $p->dims_finished($l->{lngserviceindex});

		$l->{time} = "0:00";

		$l->{equipment} = "--";

		$l->{duedate}  = $p->due_date();
		$l->{delivery} = $p->delivery_method();
		$l->{stock} = $p->stock_name($l->{lngserviceindex});
		$l->{sheets} = $p->sheet_count($l->{lngserviceindex});
		$l->{sheet_size} = $p->sheet_size($l->{lngserviceindex});




		my $con =  $dbh->selectrow_hashref(q{ 
			SELECT * FROM tbl_customer_users WHERE lnguserid = ?
		}, undef, $l->{lnguserid});
		
		$l->{contact} = "$con->{strfirstname} $con->{strlastname}";


		my $d = {};
		foreach my $c ( @{$cols} )  {
			my %x = %{$c};

			$x{value} = $l->{$c->{id}};

			push @{$d->{fields}}, \%x; 

		}
		push @data, $d;
	}
	
	#@data = grep { $_->{strprojectreference} } @data;



	apply_filters($param, \@data);
	
	
	page_options($var, $param);


	$var->{data} = \@data;

	map { $var->{__FillInForm}{$_} = $param->{$_} } keys %{$param};

	return ;

}

sub page_options {
	my $var 	= shift;
	my $param 	= shift;
	my $dbh 	= session::dbh;

	my $data = $dbh->selectall_arrayref(q{
		SELECT lngcustomerid, strcompanyname FROM tbl_customer ORDER by 2 LIMIT 5
	}, {});

	$var->{Company_Name} = ssi::make_drop_down($data);

	print STDERR "HAVE COMPANY" , Dumper($data, $var->{Company_Name});


}


sub apply_filters {
    my $param 	= shift;
    my $data 	= shift;

	

    my $searchstring = $param->{textsearch};

    if ( $searchstring ) {

		my $searchfield = $param->{search_type};

		@{$data} = filter( $searchfield, $searchstring, $data);
	
    }

	@{$data} = filter_date($param, $data);

    print STDERR "HAVE PARAMS", Dumper($param);


}

sub filter_date { 
	my $param = shift;
	my $data = shift;


	my $start = $param->{startdate};
	my $end   = $param->{enddate};

	print STDERR "HAVE DATE COMP  $start,  $end \n";

	my $dp = '%y-%m-%d';


	my $sd = DateTime::Format::Strptime->new( pattern=> '%D' )->parse_datetime($start);
	my $ed = DateTime::Format::Strptime->new( pattern=> '%D' )->parse_datetime($end);


	my @newdata;



	foreach my $row ( @{$data} ) {


		my @field = grep { $_->{id} eq 'duedate' } @{$row->{fields}};

		my $dd = $field[0]{value};

		my $duedate = DateTime::Format::Strptime->new( pattern=> $dp )->parse_datetime($dd);


		my $startcmp = $duedate->compare($sd);
		my $endcmp   = $duedate->compare($ed);

		print STDERR "COMPARE START DATE DUE: $duedate -- $startcmp ** $endcmp SD: $sd ED: $ed \n";

		if ( int($startcmp) >= 0 && int($endcmp) <= 0  ) {  
			print STDERR "HAVE DATE  NOW:  \n";
			push @newdata, $row;
		}

		print STDERR "\n";



	}

	return @newdata;

}

sub filter {
	my $f = shift;
	my $s = shift;
	my $data = shift;

	my @newdata;
	foreach my $row ( @{$data} ) {
		my @field = grep { $_->{id} eq $f } @{$row->{fields}};
		print STDERR "HAVE FIELD: " , Dumper(\@field);
		push @newdata, $row if $field[0]{value} =~ /$s/;
	}

	return @newdata;
}

1;

__END__
~       
