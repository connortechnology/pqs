package eprint::bills;

use Apache2::Const qw(:common HTTP_MOVED_TEMPORARILY); # Offers OK, Error, etc for web server.
use strict;

use session;

use Data::Dumper;

use PQS::Object::project;
use DateTime;
use DateTime::Format::Strptime;
use PQS::model::bills;


our $cols = [
	{ desc=>"ID", 					id=>"id", 					class=> "smfield", ro=>1 },
	{ desc=>"Company", 				id=>"strcompanyname", 		class=> "mdfield", ro=>1 },
	{ desc=>"Category", 			id=>"name", 				class=> "srfield", ro=>1 },
	{ desc=>"Bill Date", 			id=>"billdate", 			class=> "rgfield", ro=>1 },
	{ desc=>"Due Date", 			id=>"duedate", 				class=> "rgfield", ro=>1 },
	{ desc=>"Amount", 				id=>"amount", 				class=> "rgfield", ro=>1 },
	{ desc=>"Description", 			id=>"description", 			class=> "lgfield", ro=>1, big=>1 },

	];

sub add_link {
    my $x = shift;
    my $l = shift;

    $x->{link} = "/administrator/managerial/accounting_bills.html?editbill=$x->{value}" if $x->{id} eq 'id';


}

sub get_bill {
	my $id = shift;
	my $var = shift;


	my $bill = PQS::model::bills::get($id);

	map { $var->{__FillInForm}{$_} = $bill->{$_} } keys %{$bill};

	print STDERR "HAVE BILL ", Dumper($bill);

}


sub display {
	my ( $param, $var ) = @_;

	my $dbh = session::dbh;

	my @col_list = @{$cols};

	save_bill($param) if  $param->{save};
	get_bill($param->{editbill}, $var) if  $param->{editbill};


	
	my @data = get_data($param, \@col_list);

	$var->{fields} = \@col_list;
	$var->{data} = \@data;




	$var->{BILL_CATEGORY} = ssi::select_options(qw(bill_category id name));

	my $list = $dbh->selectall_arrayref(q{SELECT lngcustomerid, strcompanyname  
		FROM tbl_customer
		WHERE ysnsupplier = 'Y' ORDER BY 2}); 

	$var->{COMPANY} = ssi::make_drop_down($list);

	

	#Always Reset action box before loading page
	#$param->{selectall} = undef;

	map { $var->{__FillInForm}{$_} = $param->{$_} } keys %{$param};

	print STDERR "HAVE FILL " , Dumper($var->{__FillInForm} );

}


sub save_bill {
	my $param = shift;;

	print STDERR "SAVE BILL \n";

	my $company = $param->{company};
	my $category = $param->{category};

	die unless $company && $category;

	my $id = $param->{editbill} || PQS::model::bills::insert($company, $category);

	$param->{billdate} = 'NOW()' unless $param->{billdate};
	$param->{duedate} = 'NOW()' unless $param->{duedate};

	print STDERR "HAVE PARAMS" , Dumper($param);

	PQS::model::bills::update($param, $id);


}
sub sql_filters {

	my $param = shift;
	my $type = shift;


	print STDERR "START SQL FILTER \n";
	#	my $list = [
	#	{ input => 'ddmCompanyName', 	col => 'p.lngcustomerid' },
	#	{ input => 'ddmSalesRep',    	col => 'c.lngsalesperson' },
	#	{ input => 'ddmOrderBy',     	col => 'p.lnguserindex' },
	#	{ input => 'ddmProjectStatus',  col => 'p.strstatus' },
	#	{ input => 'ddmCSR',  			col => 'c.csr' },
	#];



	my $text; 
	#foreach my $f ( @{$list} ) {
	#	$text .= " AND $f->{col} = " . "'" .  "$param->{$f->{input}}" . "'" if $param->{$f->{input}};
	#}

	print STDERR "HAVE TEXT: $text \n";
	return $text;

}

sub get_data {
	my $param = shift;
	my $col_list = shift;

	my $dbh = session::dbh;

	my $sql_filter = sql_filters($param );
	my $table;


	my $sql = qq{
		SELECT bills.*, bill_category.name, tbl_customer.strcompanyname 
		FROM  
		bills, bill_category, tbl_customer
	   	WHERE  bills.category = bill_category.id 
		AND tbl_customer.lngcustomerid = bills.company


		$sql_filter

		ORDER by 1 DESC

		--LIMIT 2 
	};

	my $lines = $dbh->selectall_arrayref( $sql, {Slice => {}} );

print STDERR "HAVE SQL: $sql \n";


	my @data;

	my $sortfield = $param->{sortfield};

	print STDERR "HAVE SORT FIELD: $sortfield \n";

	foreach my $l ( @{$lines} ) {


		my $d = {};
		foreach my $c ( @{$col_list} )  {
			my %x = %{$c};


			$x{value} = $l->{$c->{id}};
			
			add_link(\%x, $l);


			push @{$d->{fields}}, \%x; 
			$d->{sortdata} = $l->{$sortfield};
			$d->{id} = $l->{strid};

		}


		#print STDERR "HAVE DATA: ",Dumper($l);
		push @data, $d;
	}


	#print STDERR "HAVE DATA X: ", Dumper(\@data);
	print STDERR "# of Records: ", scalar @data , "\n";
	return @data;

}





1;

__END__
~       
