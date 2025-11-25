package openprint::main_dashboard;

use strict;
use openprint ();
use vars qw( $r $log $dbh %variable %param %session %config );
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;

use Data::Dumper;

require openprint::Project;
require openprint::Order;
require openprint::QuotedProject;
use DateTime;
use DateTime::Format::Strptime;

our @cols = (
  { desc=>"Order",         id=>"order_id",       class=> "srfield", ro=>1 },
  { desc=>"Quote",         id=>"lngquoteid",       class=> "srfield", ro=>1 },
  { desc=>"Project",         id=>"project_id",     class=> "srfield", ro=>1 },
  { desc=>"Customer",       id=>"name",     class=> "lgfield", ro=>1 },
  { desc=>"Contact",         id=>"contact",         class=> "rgfield", ro=>1 },
  { desc=>"Status",         id=>"status",         class=> "rgfield", ro=>1 },
  { desc=>"Project Type",     id=>"ptype",         class=> "smfield", ro=>1 },
  { desc=>"Qty",           id=>"ordered_quantity",     class=> "srfield", ro=>1 },
  { desc=>"Inks",         id=>"inks",         class=> "srfield", ro=>1 },
  { desc=>"Job Name",       id=>"strprojectreference",  class=> "lgfield", ro=>1 },
#  { desc=>"Department",       id=>"department",       class=> "srfield", ro=>1 },
  { desc=>"Equipment",       id=>"equipment",       class=> "srfield", ro=>1 },
  { desc=>"Finished Size",    id=>"finished",       class=> "srfield", ro=>1 },
  { desc=>"Time",         id=>"time",         class=> "smfield", ro=>1 },
  { desc=>"Due Date",       id=>"duedate",         class=> "srfield", ro=>1 },
  { desc=>"Delivery Method",     id=>"delivery",       class=> "smfield", ro=>1 },
  { desc=>"Stock",         id=>"stock",         class=> "lgfield", ro=>1 },
  { desc=>"Sheet Size",       id=>"sheet_size",      class=> "smfield", ro=>1 },
  { desc=>"Sheets",         id=>"sheets",         class=> "smfield", ro=>1 },
  { desc=>"P",           id=>"pulled",         class=> "tifield", ro=>1 },
  );
  
sub add_link {
  my $x = shift;
  my $l = shift;

  $x->{link} = "/main/order/history_details.html?order_id=$x->{value};ddmCustomer=$l->{lngcustomerid}" if $x->{id} eq 'order_id';
  $x->{link} = "/main/project/view.html?project_id=$x->{value}" if $x->{id} eq 'project_id';
  $x->{link} = "/administrator/managerial/company_profiles.html?ddmCustomer=$l->{company_id}" if $x->{id} eq 'name';
  $x->{link} = "/administrator/managerial/user_profiles.html?ddmUser=$l->{contactid}" if $x->{id} eq 'contact';
  $x->{link} = "/main/project/view.html?pid=$l->{lngprojectindex}" if $x->{id} eq 'strprojectreference';
  $x->{link} = "/main/project/create_edit.html?project_id=$l->{lngprojectindex}" if $x->{id} eq 'intquantity1';
  $x->{link} = "/service/shipping?pid=$l->{lngprojectindex};sid=$l->{shipid}" if $x->{id} eq 'delivery';
  $x->{link} = "/service/printing?pid=$l->{lngprojectindex};sid=$l->{lngserviceindex}" if $x->{id} eq 'stock';
  $x->{link} = "/main/quote/history_details.html?quote_id=$l->{lngquoteid};" if $x->{id} eq 'lngquoteid';
}

sub sql_filters {
  my $param = shift;

  my $list = [
    { input => 'company_id',    col => 'p.company_id' },
    { input => 'ddmSalesRep',       col => 'c.salesrep_id' },
    { input => 'ddmOrderBy',        col => 'p.user_id' },
    { input => 'ddmProjectStatus', col => 'p.strstatus' },
    { input => 'ddmCSR',           col => 'c.csr' },
  ];

  my $text; 
  foreach my $f ( @{$list} ) {
    $text .= " AND $f->{col} = " . "'" .  "$param->{$f->{input}}" . "'" if $param->{$f->{input}};
  }

  if ( $param->{textsearch} && ($param->{search_type} eq 'strprojectreference')) {
    my $searchstring = lc($param->{textsearch});
    $searchstring =~ s/'//g;
    my @words = split(' ', $searchstring);
    map {
      $text .= qq{ AND lower(strprojectreference) LIKE '\%$_\%' \n}  
    } @words;
  } # end if reference

  if ( $param->{startdate} and $param->{enddate} ) {
    $text .= q{AND p.dtmcreationdate BETWEEN '} . $param->{startdate} . q{ 1:00am' AND '} . $param->{enddate} . q{ 11:59pm'};
  } elsif( $param->{startdate} ) {
    $text .= q{AND p.dtmcreationdate > '} . $param->{startdate} . q{ 1:00am'};
  }
  $log->debug("HAVE TEXT: $text");
  return $text;
}

sub dashboard_defaults {
  my $param = shift;

  return $param;
}

sub get_data {
  my $param = shift;
  my $type = shift;
  my $col_list = shift;

  my $sql_filter = sql_filters($param);

  my $sql = qq{
    SELECT *, p.strstatus as status, p.id as project_id, to_char(p.dtmcreationdate, 'YY-MM-DD') as dtmcreationdate 
    FROM projects p, companies c
    WHERE p.order_id IS NOT NULL
    AND   p.company_id = c.id

    $sql_filter

    ORDER by 1 DESC
    LIMIT 50 
  };

  my @data;
  my $lines = $dbh->selectall_arrayref( $sql, {Slice => {}} );
  $lines = [] if !$lines;
  my $sortfield = $param->{sortfield};
$log->debug("HAVE SQL: $sql sort field $sortfield lines ".@{$lines});

  foreach my $l ( @{$lines} ) {
    my $p = new openprint::Project($l);

    $l->{lngorderid} = $p->order_id;
    $l->{lngquoteid} = join(',',map {$_->quote_id()} openprint::QuotedProject->find(project_id=>$p->id));
    $l->{ptype} = $p->type();
    $l->{inks} = $p->ink_sum();
    $l->{finished} = $p->dims_finished($l->{lngserviceindex});
    $l->{time} = '0:00';
    $l->{equipment} = $p->equipment();
    $l->{duedate}  = $p->due_date();
    $l->{delivery} = $p->shipping_type();
    $l->{stock} = $p->stock_name($l->{lngserviceindex});
    $l->{sheets} = $p->parent_sheet_count($l->{lngserviceindex});
    $l->{sheet_size} = $p->sheet_size($l->{lngserviceindex});
    $l->{shipid} = $p->has_service('Shipping');
    $l->{ordered_quantity} = $p->ordered_quantity();

    my $con =  new openprint::User($l->{user_id});
    my $order = new openprint::Order($$l{order_id}) if $$l{order_id};
    
    $l->{contact} = "$con->{firstname} $con->{lastname}";
    $l->{contactid} = $con->{id};

    my $d = {};
    foreach my $c ( @{$col_list} )  {
      my %x = %{$c};
      $x{value} = $l->{$c->{id}};
      
      add_link(\%x, $l);

      push @{$d->{fields}}, \%x; 
      $d->{sortdata} = $l->{$sortfield};
      $d->{pid} = $l->{id};
    }

    $log->debug("HAVE DATA: ".Dumper($l, $con, $l->{company_id}, $con->{company_id}));
    push @data, $d;
  }

  map {
    $log->debug("HAVE SQL RESULTS:$_->{fields}[0]->{value} $_->{fields}[8]->{value}");
  } @data;
  print STDERR "# of Records: ", scalar @data , "\n";
  return @data;
}

sub action {
  my ( $action, $value, $list ) = @_;

  $log->debug("HAVE VALUES ". Dumper($action, $value, $list));

  if ($action) {
    if ( $action eq 'DueDate' ) {
      foreach my $p ( @{$list} ) {
        my $proj = new PQS::Object::project($p);
        $proj->due_date($value);
      }
    } elsif ( $action eq 'PidStatus' ) {
      $log->debug("UPDATE PID: $action");
      foreach my $p ( @{$list} ) {
        my $project = new openprint::Project($p);
        my $order = $project->Order();

        $log->debug("SET STATUS $p, $value");
        if ( $value eq 'Complete' ) {
          eprint::employee_project::complete_project($r, $dbh, $p);
        } elsif ( $value eq 'In Production' ) {
          #prevent completion date trigger in db;
          openprint::project::project_status($dbh, $p, $value );
          #Reset Completion date.
          $dbh->do(q{UPDATE tbl_projects SET completion_date = NULL WHERE lngprojectindex = ?},undef,  $p);
          $dbh->do(q{UPDATE tbl_projects SET files = true WHERE lngprojectindex = ?},undef,  $p);
          #Clear Deposit database field to prevent status returning to pending deposit.
          $order->deposit_not_required();
        } else {
          openprint::project::project_status($dbh, $p, $value );
          print STDERR "SET PROJECT STATUS $p = $value \n";
        }

        $project->update_status();
      }
    } elsif ( $action eq 'OrderStatus' ) {
      foreach my $p ( @{$list} ) {
        my $order = PQS::model::order::get_order_by_pid($p);

        if ( $value eq 'Cancel' ) {
          openprint::order::cancel_order($r, $log, $dbh, $order->{lngorderid});
        } elsif ( $value eq 'Complete' ) {
          print STDERR "STATUS TIME TO COMPLETE PROJECT: $p \n";
          # here complete_order?? tbl_order doesn't change
          openprint::employee_project::complete_project($r, $dbh, $p);
        } else {
          print STDERR "SET ORDER STATUS $p, $value, $order \n";
          PQS::model::order::set_status( $order->{lngorderid}, $value);
        }

      }
    } elsif ( $action eq 'PriorityStatus' ) {
      print STDERR "UPDATE PRIORITY \n";
      foreach my $p ( @{$list} ) {
        my $proj = new openprint::Project($p);
        PQS::model::project::set_priority_status( $proj->{id}, $value);
      }
    }
  } # end if action
} # end sub action

sub text_search {
  my $param = shift;
  my $var   = shift;

  my $search_type = $param->{search_type};

  if ( $search_type eq 'lngprojectindex' || $search_type eq 'lngorderid' || $search_type eq 'lngquoteid' ) {
    my $ref = lc($param->{'textsearch'});
    $ref =~ /(\d*)/;

    my $is_num = eprint::print_project::is_integer($ref); 
    
    my $redirect;
    my $cust;
    my $pid;
    if ( $search_type eq 'lngprojectindex' ) {
      ($pid, $cust) = $is_num ? $dbh->selectrow_array(q{
        SELECT lngprojectindex, lngcustomerid FROM tbl_projects WHERE lngprojectindex = ?
      }, undef, $ref) : undef;

      print STDERR "HAVE SEARCH: $search_type, PID: $pid, CUST: $cust, REF: $ref \n";

      if ( $pid ) {
        $var->{param}{pid} = $pid;
        $redirect = "/main/proj/proj_view.html?pid=$pid";
      }
    }

    if ( $search_type eq 'lngorderid' ) {

      my $order;
      my $ocust;
      ($order, $ocust)  = $1 ? $dbh->selectrow_array(q{
        SELECT lngorderid, lngcustomerid FROM tbl_orders WHERE lngorderid = ?
      }, undef, $1) : undef;

      print STDERR "HAVE SEARCH: $search_type, ORDER $order, CUST: $cust, REF: $ref \n";

      if ( $order ) {
        $var->{param}{order_id} = $order;
        $redirect = "/main/order/order_history_details.html?order_id=$order";
        $cust = $ocust;
      }
    }

    if ( $search_type eq 'lngquoteid' ) {

      my $quote;
      my $ocust;
      ($quote, $ocust) = $1 ? $dbh->selectrow_array(q{
        SELECT lngquoteid, lngcustomerid FROM tbl_quotes WHERE lngquoteid = ?
      }, undef, $1) : undef;

      print STDERR "HAVE SEARCH: $search_type, ORDER $quote, CUST: $ocust, REF: $ref \n";

      if ( $quote ) {
        $var->{param}{quote_id} = $quote;
        $redirect = "/main/quote/quote_history_details.html?quote_id=$quote";
        $cust = $ocust;
      }
    }

    if ( $redirect ) {
      die("have cust: $cust, $var->{cookie} ") unless $cust;
      eprint::login::select_customer( $r, $log, $dbh, $var->{cookie}, $var, $cust );
      print STDERR "HAVE REDIRECT: $redirect \n";
      $var->{Redirect} = $redirect;
      return;
    }
  }
}

sub dashboard {
  if ( $param{textsearch} ) {
    text_search(\%param, \%variable);
    return if $variable{Redirect};
  }

  my ($action, $value) = split /:/, $param{action};

  if ( $param{duedate} ) {
    $action = 'DueDate';
    $value  = $param{duedate} if $param{duedate};
  }

  my $list = $param{actionpid};

  #Convert List to arrary ref if only single item was selected.
  $list = [$list] if ($list && ref $list ne 'ARRAY');

  action($action, $value, $list) if $action;

  # Set defaults
  #my $today = DateTime->now->strftime('%m/%d/%Y');
  #my $strp = DateTime::Format::Strptime->new( pattern => '%m/%d/%Y');
  #my $dt =  $strp->parse_datetime($today);

  #my $s = 0;
  #my $e = 90;

  #$param->{startdate}   = $dt->add(days => -$s)->strftime('%m/%d/%Y') unless $param->{startdate};
  #$param->{enddate}     = $dt->add(days => $s + $e)->strftime('%m/%d/%Y') unless $param->{enddate};

  $param{ddmProjectStatus} = 'In Production' unless defined $param{ddmProjectStatus} ;
  $param{reportType} = 'Order' unless $param{reportType};

  my $type = $param{reportType};

  my @col_list = @cols;
  splice @col_list, 1,1 if $type eq 'Order'; 
  splice @col_list, 0,1 if $type eq 'Quote'; 
  
  my @data = get_data(\%param, $type, \@col_list);

  apply_filters(\%param, \@data);

  $openprint::log->error("# of records after filters: ". scalar @data);

  apply_sort(\@data, \%param);
  page_options(\%variable, \%param);

  $variable{fields} = \@col_list;
  $variable{data} = \@data;
  $variable{startdate} = $param{startdate};
  $variable{enddate}   = $param{enddate};

  #Always Reset action box before loading page
  $param{action} = undef;
  $param{actionpid} = undef;
  $param{selectall} = undef;

  map { $variable{__FillInForm}{$_} = $param{$_} } keys %param;

  #print STDERR "HAVE DATA", Dumper($var->{data});
  return;
}

sub apply_sort {
  my $data = shift;
  my $param = shift;

  my $x = int($$data[0]->{sortdata});
  my $y = $$data[0]->{sortdata};

  use Scalar::Util qw( looks_like_number );
  if ( looks_like_number($$data[0]->{sortdata}) ) {
    @{$data} = sort { $a->{sortdata} <=> $b->{sortdata} } @{$data};
  } else { 
    @{$data} = sort { $a->{sortdata} cmp $b->{sortdata} } @{$data};
  }
  if ( $param->{sortdirection} == -1 ) {
    print STDERR "REVERSE SORT \n";
    @{$data} = reverse @{$data};
  }
}

sub page_options {
  my $var   = shift;
  my $param   = shift;

  my $sql = $dbh->selectall_arrayref(q{ 
    SELECT id, name FROM companies ORDER by 2
  }, {});

  $var->{Company_Name} = ssi::make_drop_down($sql);

  my $sql = $dbh->selectall_arrayref(q{ 
    SELECT id, firstname || ' ' || lastname FROM users 
    WHERE ( type = 'A' or type = 'E') ORDER by lower(lastname), lower(firstname)
       --LIMIT 5 
  }, {});

  $var->{EmployeeList}   = ssi::make_drop_down($sql);

  $sql = $dbh->selectall_arrayref(q{ 
    SELECT id, firstname || ' ' || lastname FROM users 

    --WHERE ( type = 'A' or type = 'E') 

    ORDER by lower(lastname), lower(firstname)

       --LIMIT 5 
  }, {});

  $var->{CustomerList}   = ssi::make_drop_down($sql);
}

sub apply_filters {
  my $param   = shift;
  my $data   = shift;

  #User Text Search
  my $searchstring = $param->{textsearch};

  if ( $searchstring ) {
    my $searchfield = $param->{search_type};
    # Teach searches have be moved to other areas
    #@{$data} = filter( $searchfield, $searchstring, $data);
  }

  #Date field search
  #Moved to sql filter
  #@{$data} = filter_date($param, $data);

  print STDERR "HAVE PARAMS", Dumper($param);
}

sub filter_date { 
  my $param = shift;
  my $data = shift;

  my $start = $param->{startdate};
  my $end   = $param->{enddate};

  return @$data unless $start && $end;

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

    #    print STDERR "COMPARE START DATE DUE: $duedate --  $sd ED: $ed \n";

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
    #print STDERR "HAVE FIELD: " , Dumper(\@field);
    push @newdata, $row if $field[0]{value} =~ /$s/;
  }

  return @newdata;
}

1;

__END__
~       
