use strict;
use warnings;

package openprint::tasks;
use openprint;
use vars qw( %variable %session %param %config $log $dbh $r );
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*r = \$openprint::r;

require openprint::Task;
require openprint::Host;
require openprint::Location;

use Data::Dumper;

sub index {
}

sub list {
	_list();
	ssi::setup_date_select( $r->uri(), 'created_on_start', '' );
	ssi::setup_date_select( $r->uri(), 'created_on_end', '' );
	ssi::setup_date_select( $r->uri(), 'updated_on_start', '' );
	ssi::setup_date_select( $r->uri(), 'updated_on_end', '' );
} # end sub list

sub _list {
  if ($param{action}) {
    if ( $param{action} eq 'Delete' ) {
      foreach my $task_id ( ref $param{'task_id[]'} eq 'ARRAY' ? @{$param{'task_id[]'}} : $param{'task_id[]'} ) {
        my $Task = new openprint::Task( $task_id );
        $variable{error} .= $Task->delete();
      } # end foreach task_id
      %param = ();
    } else {
      $log->error("Unknown action $param{action}");
    } # end if
	} # end if
	ssi::save_params( '/tasks/list.html', 
    ( map { 'created_on_start_' . $_ } ( 'year', 'month', 'day' ) ),
    ( map { 'created_on_end_' . $_ } ( 'year', 'month', 'day' ) ),
    ( map { 'updated_on_start_' . $_ } ( 'year', 'month', 'day' ) ),
    ( map { 'updated_on_end_' . $_ } ( 'year', 'month', 'day' ) ),
    'order',
  );
} # end sub _tasks

sub view {
  my $Task = $variable{Task} = new openprint::Task( openprint::Task->transform(id=>$param{task_id}) );
}

sub edit {
  my $Task = $variable{Task} = new openprint::Task( openprint::Task->transform(id=>$param{task_id}) );
  if ($param{action}) {
    if ( $param{action} eq 'Delete' ) {
      $variable{error} .= $Task->delete();
      if (!$variable{error}) {
        $variable{ExternalRedirect} = '/tasks/list.html';
        %param = ();
      } # end if
    } elsif ( $param{action} eq 'Save' ) {
      my $Task = new openprint::Task( $param{task_id} );
      $variable{error} .= $Task->save(\%param);
      if ( ! $variable{error} ) {
        %param = ();
        $variable{ExternalRedirect} = '/tasks/list.html';
      } # end if
    } # end if
  } # end if param
} # end sub edit

sub _host_popup {
	my $Task = $variable{Task} = new openprint::Task($param{task_id});
	if ( ! $Task->id() ) {
		$variable{error} .= 'Task not found.';
		return;
	} # end if
} # end sub _host_popup

sub _host_results {
	my $Task = $variable{Task} = new openprint::Task($param{task_id});
	if ( ! $Task->id() ) {
		$variable{error} .= 'Task not found.';
		return;
	} # end if
} # end sub _host_results

sub _hosts {
  my $Task = $variable{Task} = new openprint::Task($param{task_id});
  if ( ! $Task->id() ) {
    $variable{error} .= 'Task not found.';
    return;
  } # end if
  if ($param{action}) {
    if ( $param{action} eq 'allocate' ) {
      my $Host = new openprint::Host($param{host_id});
      if ( ! $Host->id() ) {
        $variable{error} .= 'Host not found.';
        return;
      } # end if

      my $SH = new openprint::Host_Task();
      $variable{error} .= $SH->save({task_id=>$param{task_id}, host_id=>$param{host_id}});
    } elsif ( $param{action} eq 'delete' ) {
      my $SH = openprint::Host_Task->find_one( task_id=>$param{task_id}, host_id=>$param{host_id} );
      if ( ! $SH ) {
        $variable{error} .= 'Allocation not found.';
        return;
      } 
      $variable{error} .= $SH->delete();
    } # end if	
	} # end if action
} # end sub _hosts

1;
__END__
