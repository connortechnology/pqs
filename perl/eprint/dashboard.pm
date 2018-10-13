package eprint::dashboard;

use Apache2::Const qw(:common HTTP_MOVED_TEMPORARILY); # Offers OK, Error, etc for web server.
use strict;

use session;

use Data::Dumper;

use PQS::Object::project;
use DateTime;
use DateTime::Format::Strptime;

our $dbh = session::dbh;

	our $cols = [
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
  
sub add_link {
    my $x = shift;
    my $l = shift;

    $x->{link} = "/main/order/order_history_details.html?orderid=$x->{value}" if $x->{id} eq 'lngorderid';
    $x->{link} = "/main/proj/proj_view.html?pid=$x->{value}" if $x->{id} eq 'lngprojectindex';
    $x->{link} = "/administrator/managerial/company_profiles.html?ddmCustomer=$l->{lngcustomerid}" if $x->{id} eq 'strcompanyname';
}

sub sql_filters {

	my $param = shift;

	my $list = [
		{ input => 'ddmCompanyName', 	col => 'o.lngcustomerid' },
		{ input => 'ddmSalesRep',    	col => 'c.lngsalesperson' },
		{ input => 'ddmOrderBy',     	col => 'o.lnguserid' },
		{ input => 'ddmProjectStatus',  col => 'p.strstatus' },
		{ input => 'ddmCSR',  			col => 'c.csr' },
	];


	my $text; 
	foreach my $f ( @{$list} ) {
		$text .= " AND $f->{col} = " . "'" .  "$param->{$f->{input}}" . "'" if $param->{$f->{input}};

	}

	print STDERR "HAVE TEXT: $text \n";
	return $text;

}

sub dashboard_defaults {
	my $param = shift;

	my $today = DateTime->now->strftime('%m/%d/%Y');

	my $strp = DateTime::Format::Strptime->new( pattern => '%m/%d/%Y');

	my $dt =  $strp->parse_datetime($today);

	my $s = 100;
	my $e = 30;

	$param->{startdate}   = $dt->add(days => -$s)->strftime('%m/%d/%Y') unless $param->{startdate};
	$param->{enddate}     = $dt->add(days => $s + $e)->strftime('%m/%d/%Y') unless $param->{enddate};

	return $param;
	print STDERR "SET APRAMS: " ,Dumper($param);
}

sub get_data {
	my $param = shift;

	my $dbh = session::dbh;

	my $sql_filter = sql_filters($param);

	my $sql = qq{
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

		$sql_filter

		ORDER by o.lngorderid DESC
		LIMIT 30 
	};

	my $lines = $dbh->selectall_arrayref( $sql, {Slice => {}} );

print STDERR "HAVE SQL: $sql \n";


	my @data;

	my $sortfield = $param->{sortfield};

	print STDERR "HAVE SORT FIELD: $sortfield \n";

	foreach my $l ( @{$lines} ) {

		#print STDERR "HAVE LINE $l->{lngorderid} \n";

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
			
			add_link(\%x, $l);


			push @{$d->{fields}}, \%x; 
			$d->{sortdata} = $l->{$sortfield};
			$d->{pid} = $l->{lngprojectindex};

		}
		push @data, $d;
	}
	return @data;

}

sub action {


}

sub display {
	my $var = shift;
	my $param = shift;


	$param = dashboard_defaults($param);

	
	my @data = get_data($param);

	apply_filters($param, \@data);




	action($param, \@data) if $param->{action};

	apply_sort(\@data);

	page_options($var, $param);


	$var->{fields} = $cols;

	$var->{data} = \@data;

	$var->{startdate} 	= $param->{startdate};
	$var->{enddate} 	= $param->{enddate};

	map { $var->{__FillInForm}{$_} = $param->{$_} } keys %{$param};

	#print STDERR "HAVE DATA", Dumper($var->{data});

	return ;

}


sub apply_sort {
	my $data = shift;


	my $x = int($$data[0]->{sortdata});

	my $y = $$data[0]->{sortdata};

	use Scalar::Util qw( looks_like_number );

	if ( looks_like_number($$data[0]->{sortdata}) ) {
	    @{$data} = sort { $a->{sortdata} <=> $b->{sortdata} } @{$data};
	} else { 
	    @{$data} = sort { $a->{sortdata} cmp $b->{sortdata} } @{$data};
	}
}


sub page_options {
	my $var 	= shift;
	my $param 	= shift;
	my $dbh 	= session::dbh;

	my $sql = $dbh->selectall_arrayref(q{ 
		SELECT lngcustomerid, strcompanyname FROM tbl_customer ORDER by 2
	}, {});

	$var->{Company_Name} = ssi::make_drop_down($sql);

	my $sql = $dbh->selectall_arrayref(q{ 
		SELECT lnguserid, strfirstname || ' ' || strlastname FROM tbl_customer_users 
		WHERE ( chrtype = 'A' or chrtype = 'E') ORDER by strlastname, strfirstname
	   	--LIMIT 5 
	}, {});

	$var->{EmployeeList} 	= ssi::make_drop_down($sql);


	my $sql = $dbh->selectall_arrayref(q{ 
		SELECT Distinct  strStatus, strStatus  FROM tbl_projects ORDER by 1
	}, {});

	$var->{ProjectStatus} = ssi::make_drop_down($sql);





	#print STDERR "HAVE COMPANY" , Dumper($data, $var->{Company_Name});


}


sub apply_filters {
    my $param 	= shift;
    my $data 	= shift;

	
	#User Text Search
    my $searchstring = $param->{textsearch};

    if ( $searchstring ) {

		my $searchfield = $param->{search_type};

		@{$data} = filter( $searchfield, $searchstring, $data);
	
    }


	#Date field search
	@{$data} = filter_date($param, $data);

    print STDERR "HAVE PARAMS", Dumper($param);


}

sub filter_date { 
	my $param = shift;
	my $data = shift;


	my $start = $param->{startdate};
	my $end   = $param->{enddate};

	return  @$data unless $start && $end;


	my $dp = '%y-%m-%d';


	my $sd = DateTime::Format::Strptime->new( pattern=> '%m/%d/%Y' )->parse_datetime($start);
	my $ed = DateTime::Format::Strptime->new( pattern=> '%m/%d/%Y' )->parse_datetime($end);

	print STDERR "HAVE DATE COMP  START $start -> $sd, END   $end -> $ed \n";


	my @newdata;

	#print STDERR "HAVE DATA" , Dumper($data);



	foreach my $row ( @{$data} ) {


		my @field = grep { $_->{id} eq 'duedate' } @{$row->{fields}};

		my $dd = $field[0]{value};

		next unless $dd;

		my $duedate = DateTime::Format::Strptime->new( pattern=> $dp )->parse_datetime($dd);


		#		print STDERR "COMPARE START DATE DUE: $duedate --  $sd ED: $ed \n";

		my $startcmp = $duedate->compare($sd);
		my $endcmp   = $duedate->compare($ed);
		#print STDERR "COMPARE START DATE DUE: $duedate -- $startcmp ** $endcmp SD: $sd ED: $ed \n";


		if ( int($startcmp) >= 0 && int($endcmp) <= 0  ) {  
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
