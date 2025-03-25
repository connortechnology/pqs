use strict;
package openprint::main_quote;

use openprint ();
use vars qw( $r $log $dbh %variable %param %session %config );
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;

require sql;
require ssi;
require misc;
require configuration;
require openprint::Currency;
require openprint::Project;
require openprint::Quote;
require openprint::QuotedProject;
require openprint::quote;

sub try_to_delete {
  my $Quote = shift;
  if ( $Quote->can_delete() ) {
    $Quote->delete();
    $Quote->add_log('Deleted');
  } else {
    return "Quote $$Quote{id} does not belong to you.  Not deleted.<br>";
  } # end if
  return '';
} # end sub try_to_delete

sub history {

  if ($param{btnFunction}) {
    if ( $param{btnFunction} eq 'Delete' ) {
      foreach my $Quote (openprint::Quote->find(id=>[(ref $param{quote_id} eq 'ARRAY') ?  @{$param{quote_id}} : ($param{quote_id})])) {
        $variable{error} .= try_to_delete($Quote);
      } # end foreach
    } elsif ( $param{btnFunction} eq 'Undelete' ) {
      foreach my $Quote (openprint::Quote->find(id=>[(ref $param{quote_id} eq 'ARRAY') ?  @{$param{quote_id}} : ($param{quote_id})])) {
        $variable{error} .= $Quote->undelete();
      } # end foreach
    } elsif ($param{btnFunction} eq 'destroy') {
      foreach my $Quote (openprint::Quote->find(
          deleted=>1,
          id=>[(ref $param{quote_id} eq 'ARRAY') ?  @{$param{quote_id}} : ($param{quote_id})])) {
        if (!$Quote->deleted()) {
          $variable{error} .= 'Can\'t destroy quote '.$$Quote{id}.' since it isn\'t deleted.<br/>';
          next;
        }
        $variable{error} .= $Quote->destroy();
      } # end foreach
    } elsif ( $param{btnFunction} eq 'Download in CSV format' ) {

      my @header = ( 'Quote ID', 'Created On', 'Prepared By', 'Company', 'Prepared For','Status', 'Currency', 
        'Total 1', 'Total 2', 'Total 3',
        'Project Quantity 1', 'Project Price 1',
        'Project Quantity 2', 'Project Price 2',
        'Project Quantity 3', 'Project Price 3',
        'Ordered Quantity', 'Ordered Price', 'Docket' );
      my @data;
      my $total1;
      my $total2;
      my $total3;
      foreach my $Quote ( @{$variable{Quotes}} ) {
        foreach my $QP ( $Quote->Quoted_Projects() ) {
          my $Project = $QP->Project();

          push @data, (
            $Quote->id(), ssi::format_csv_datetime($Quote->created_on()),
            $Quote->by_name(), $Quote->Company()->name(), $Quote->for_name(), $Quote->status(),
            $Quote->Currency()->name(),
            $Quote->total1(), $Quote->total2(), $Quote->total3(),
            $QP->quantity1(), $QP->price1(),
            $QP->quantity2(), $QP->price2(),
            $QP->quantity3(), $QP->price3(),
            $Project->ordered_quantity(),
            $Project->ordered_price(),
            $Project->docket(),
          );
        } # end foreach Project
        $total1 += $Quote->total1();
        $total2 += $Quote->total2();
        $total3 += $Quote->total3();
      } # end foreach
      push @data, '','','','','','', 'Totals:', $total1, $total2, $total3, '', '', '', '', '', '';
      misc::export_csv( $r, $log, \%variable, 'quote_report.csv', \@header, \@data );
    } else {
      $log->error("Unknown btnFunction in quote history $param{btnFunction}");
    } # end if
  } else {
    ssi::setup_date_select($r->uri(), 'created_on_start', -30);
    ssi::setup_date_select($r->uri(), 'created_on_end', 0);
    $session{$r->uri().'?company_id'} = $session{company_id} if ! exists $session{$r->uri().'?company_id'};
    $session{$r->uri().'?deleted'} = '0' if ! exists $session{$r->uri().'?deleted'};
    #$session{$r->uri().'?limit'} = '1000' if ! exists $session{$r->uri().'?limit'};
  }

  _history();
} # end sub history

sub _history {
  my $uri = '/main/quote/history.html';
  if (!$param{btnFunction}) {
  ssi::save_params($uri,
      'created_on_start_year', 'created_on_start_month','created_on_start_day',
      'created_on_end_year', 'created_on_end_month','created_on_end_day',
			'user_id',
      'QuotedFor', 'company_id','deleted','salesrep_id', 'status', 'total_start','total_end','limit','press_id','ordered',
      );
  }
  if ( $param{QuoteID} ) {
    $variable{Quotes} = [ openprint::Quote->find(
        ( sets::isin($session{user_type}, ['E','A'] ) ? () : ( company_id   =>  $session{company_id} ) ),
        'id like'   =>  '%'.$param{QuoteID}.'%',
        deleted=>[0,1],
        ) ];
  } else {
    my $Press = new openprint::Equipment( $param{press_id} ) if $param{press_id};
    @{$variable{Quotes}} = ();

		my @Quotes = openprint::Quote->find(
        ( sets::isin($session{user_type}, ['E','A']) ? (
          ( $session{$uri.'?company_id'} ? ( company_id=>$session{$uri.'?company_id'}) : () ),
          ( $session{$uri.'?user_id'} ? ( user_id=>$session{$uri.'?user_id'}) : () ),
)
 :
          ( company_id =>   $session{company_id} )
        ),
        ( $session{$uri.'?QuotedFor'} ? ( 'for_name ilike' => '%'.$session{$uri.'?QuotedFor'}.'%' ) : () ),
        ssi::date_filter( $uri.'?created_on_end', 'created_on <=' ),
        ssi::date_filter( $uri.'?created_on_start', 'created_on >=' ),
        ( $session{$uri.'?deleted'} eq '' ? () : ( deleted=>$session{$uri.'?deleted'} ) ),
        ( map { $session{$uri.'?'.$_} ? ( $_ => $session{$uri.'?'.$_} ) : () } ( 'status', 'salesrep_id' ) ),
        ( ( $session{$uri.'?total_start'} or $session{$uri.'?total_end'} ) ?
          (
           and => [ ( $session{$uri.'?total_start'} ? ( or => { 
               'total1 >=' => $session{$uri.'?total_start'},
               'total2 >=' => $session{$uri.'?total_start'},
               'total3 >=' => $session{$uri.'?total_start'},
               } ) : () ),
           ( $session{$uri.'?total_end'} ?
             ( or => { 
               'total1 <=' => $session{$uri.'?total_end'},
               'total2 <=' => $session{$uri.'?total_end'},
               'total3 <=' => $session{$uri.'?total_end'},
               } ) : () ),
					 ] ) : () ),
				order =>  $openprint::Quote::fields{created_on}.' DESC',
				limit =>   $session{$uri.'?limit'} ? $session{$uri.'?limit'} : 1000,
					 );

		my @quote_ids = map { $$_{id} } @Quotes;
    return if ! @quote_ids;

		my @Quoted_Projects = openprint::QuotedProject->find(quote_id=>\@quote_ids,order=>'project_id') if @quote_ids;
		my @project_ids = map { $$_{project_id} } @Quoted_Projects;
		my %Quoted_Projects = misc::make_hash_from_array('quote_id', @Quoted_Projects);
		my @Projects = openprint::Project->find(id=>\@project_ids) if @project_ids;
		my @company_ids = map { $$_{company_id} } @Quotes;
		my @Companies = openprint::Company->find(id=>\@company_ids) if @company_ids > 1;
		my @Ordered_Projects = openprint::OrderedProject->find(project_id=>\@project_ids) if @project_ids;
		my %Ordered_Projects_by_project_id = misc::make_hash_from_array('project_id', @Ordered_Projects);
		foreach my $Project ( @Projects ) {
			$Project->Ordered_Project($Ordered_Projects_by_project_id{$$Project{id}}[0]) if $Ordered_Projects_by_project_id{$$Project{id}};
		}
		
    foreach my $Quote ( @Quotes ) {
			$Quote->Quoted_Projects( $Quoted_Projects{$$Quote{id}} ? $Quoted_Projects{$$Quote{id}} : [] );

			if ( $param{ordered} ne '' ) {
				my $keep = 0;
        foreach my $Project ( $Quote->Projects() ) {
					if ( $Project->docket() ) {
						$keep = 1;
						last;
					}
				}
				next if $param{ordered} and !$keep;
				next if $keep and !$param{ordered};
			}
			
      if ( $param{press_id} ) {
        my $on_press = 0;
        foreach my $Project ( $Quote->Projects() ) {
          foreach my $sig_id ( $Project->signatures() ) {
            my $sig_specs = openprint::service::get_specs_ref( $Project, $sig_id );
            if ( ! $$sig_specs{UsePress} ) {
              $$sig_specs{UsePress} = $$sig_specs{'ddmPress'.$Project->ordered_quantity_index()};
            } # end if
            if ( $$sig_specs{UsePress} eq $$Press{strid} ) {
              $on_press = 1;
            } # end if
            last if $on_press;
          } # end foreach sig
          last if $on_press;
        } # end foreach Project
        next if ! $on_press;
      } # end if press_id

      push @{$variable{Quotes}}, $Quote;
    } # end foreach Quote
  } # end if

} # end sub _history

sub history_details {
  $param{quote_id} = openprint::Quote->transform('id', $param{quote_id} );
  my $Quote = $variable{Quote} = new openprint::Quote( $param{quote_id} );

  if ( $param{btnFunction} eq 'Move To' ) {
    if ( ! $Quote->id() ) {
      $variable{error} .= 'Empty or invalid quote id.<br/>';
    } elsif ( ! $param{company_id} ) {
      $variable{error} = 'You must select a company first.<br/>';
    } elsif ( $Quote->company_id() == $param{company_id} ) {
      $variable{error} = $Quote->Company()->name() .' already owns that quote.  No change made.<br/>';
    } else {
      my $OldCompany = $Quote->Company();
      my $NewCompany = new openprint::Company( $param{company_id} );

      if ( $Quote->can_delete() and ( (!$$NewCompany{salesrep_id}) or ( $session{user_id} == $$NewCompany{salesrep_id} ) ) ) {
        $variable{error} .= $Quote->save({company_id=>$param{company_id}});
      } else {
        $variable{error} .= 'You do not have permission to move this quote.<br/>';
      } # end if
    } # end if
    if ( ! $variable{error} ) {
      %param = ();
      $variable{ExternalRedirect} = '/main/quote/history.html';
      return;
    } # end if
  } elsif ( $param{btnFunction} eq 'Delete' ) {
    if ( ! $Quote->can_delete() ) {
      $variable{error} .= 'You do not have permission to delete this quote.<br/>';
    } else {
      $variable{error} .= $Quote->delete();
    } # end if
    if ( ! $variable{error} ) {
      $Quote->add_log('Deleted');
      $variable{ExternalRedirect} = '/main/quote/history.html';
    } # end if
  } elsif ( $param{btnFunction} eq 'Undelete' ) {
    if ( ! $Quote->can_delete() ) {
      $variable{error} .= 'You do not have permission to undelete this quote.<br/>';
    } else {
      $variable{error} .= $Quote->save({deleted=>0});
      $Quote->add_log('Undeleted');
    } # end if
    if ( ! $variable{error} ) {
      $variable{ExternalRedirect} = '/main/quote/history_details.html?quote_id='.$Quote->id();
    } # end if
  } elsif ( $param{btnFunction} eq 'Resend' ) {
    if ( $Quote->can_send( ) ) {
      my $results = $Quote->send();
      $Quote->add_log('Resent. Results: ' . $results);
      $variable{information} .= 'Quote resent. Results: '. $results;
    } else {
      $variable{error} .= "Can't resend quote.<br/>";
    } # end if
    $variable{ExternalRedirect} = '/main/quote/history_details.html?quote_id='.$Quote->id();
    return;
  } elsif ( $param{btnFunction} eq 'SendToMe' ) {
    if ( $Quote->can_view( ) ) {
      my $results = $Quote->send( $openprint::User );
      $variable{information} .= 'Quote Sent To Me. Results: '. $results;
    } else {
      $variable{error} .= "Can't send quote. You are not allowed to view it.<br/>";
    } # end if
    $variable{ExternalRedirect} = '/main/quote/history_details.html?quote_id='.$Quote->id();
    return;
  } # end if
  openprint::quote::get_finished_quote_contents( $log, $dbh, \%variable, $$Quote{id} ) if $param{quote_id};
} # end sub history_details

sub add_project_to_quote {
  my ( $quote_id, $project_id ) = @_;

  $quote_id = $session{quote_id} if ! $quote_id;
  $quote_id = new openprint::Quote( $quote_id )->id() if $quote_id;
  my $Quote = new openprint::Quote( $quote_id );
  $Quote->save() if ! $Quote->id();
  $Quote->save({deleted=>0}) if $Quote->deleted();

  $session{quote_id} = $quote_id = $Quote->id();
  return if ! $quote_id;

  $project_id = $param{ProjectIndex} if ! $project_id;
  $project_id = $session{project_id} if ! $project_id;
  # check to make sure project isn't already in the quote.
  my @QuotedProjects = openprint::QuotedProject->find( quote_id=>$Quote->id(), project_id=>$project_id );
  if ( @QuotedProjects > 1 ) {
$openprint::log->error( 'More than 1 occurrence of a project in a quote.' );
    foreach my $QP ( @QuotedProjects ) {
      $QP->delete();
    } # end foreach QP
    @QuotedProjects = ();
  } # end if
  if ( ! @QuotedProjects ) {
    my $QP = new openprint::QuotedProject();
    my $Project = new openprint::Project($project_id);
    if ( ( my $error = $QP->save( {
            quote_id 		      =>  $Quote->id(),
            project_id  		  =>  $project_id,
            include_detailed  =>  $openprint::Company->quote_project_breakdown(),
            template_id    		=>  $openprint::User->quote_level(),
            } ) ) ) {
			$openprint::log->error($error);
    } else {
      $Quote->add_log('Added project ' . $project_id . ' prices: ' . join(', ', $Project->prices()));
      $Project->add_to_log( @openprint::session{'company_id','user_id'}, "Add to quote $quote_id prices: " . join(', ', $Project->prices() ) );
    } # end if
  } # end if
  return $quote_id;
} # end sub add_project_to_quote

# this page displays the user info page.
# It also processes and stores the information from the details page, in terms of markup, etc.
sub information {
  my $quote_id;
  if ($param{btnFunction}) {
    if ( $param{btnFunction} eq 'New' ) {
      my $Quote = new openprint::Quote();
      $variable{error} .= $Quote->save({
          user_id   		=>  $session{user_id},
          company_id  	=>  $session{company_id},
          for_company_id=>  $session{company_id},
          status 		   	=>  'Incomplete',
          Currency   	=>  openprint::Currency::get_current(),
        });
      $variable{ExternalRedirect} = '/main/quote/information.html?quote_id='.$Quote->id();
      return;
    } elsif ( $param{btnFunction} eq 'Process Quote' ) {
      $quote_id = add_project_to_quote( );
      $variable{ExternalRedirect} = '/main/quote/information.html?quote_id='.$quote_id;
      return;
    } elsif ( ($param{btnFunction} eq 'Process New Quote') and $param{quote_id} ) {
      my $Quote = new openprint::Quote( $param{quote_id} );
      if ( ! $Quote->id() ) {
        $variable{error} .= 'Invalid quote id: ' . $param{quote_id}.'<br/>';
      } # end if
      my $NewQuote = new openprint::Quote();
      $NewQuote->user_id( $session{user_id} );
      if ( $param{company_id} and 
        ( $param{company_id} != $session{company_id} ) and 
        sets::isin( $session{user_type}, ['A','E'] ) 
      ) {
        openprint::switch_company( new openprint::Company( $param{company_id} ) ) if sets::isin( $session{user_type}, ['A','E'] );
      } # end if
      $NewQuote->company_id( $session{company_id} );
      $NewQuote->status( 'Incomplete' );
      $NewQuote->currency_id($Quote->currency_id());
      $NewQuote->reference($Quote->reference());
      $NewQuote->save();
      if ( ! $NewQuote->id() ) {
        $variable{error} .= 'Unable to create new quote.<br/>';
        $log->error('Unable to create new quote.');
        return;
      } # end if

      foreach my $QP ( $Quote->Quoted_Projects() ) {
        my $NewQP = $QP->copy();
        my $Project = $QP->Project();
        my $NewProject = $Project;
        if ( $Quote->company_id() != $NewQuote->company_id() ) {
          $NewProject = $Project->copy();
          $NewProject->docket( '' );
          $NewProject->due_date( '' );
          $NewProject->user_id( $session{user_id} );
          $NewProject->order_id( '' );
          # This allows uncalc->uncalc, everything else to UnOrdered
          if ( sets::isin( $Project->status(), [ 'Pending Deposit', 'In Prepress', 'Proofs Out', 'Approved', 'Printed', 'Complete','Shipped','Picked Up' ] ) ) {
            $NewProject->status('Unordered');
          } # end if
          $NewProject->company_id( $session{company_id} );
          $NewProject->save();
          $NewProject->add_to_log( @session{'company_id','user_id'}, 'Reused from project '.$Project->id() );
          $Project->add_to_log( @session{'company_id','user_id'}, 'Reused to project '.$NewProject->id() );
        } # end if
        $variable{error} .= $NewQP->save({quote_id => $NewQuote->id(), project_id => $NewProject->id() });
      } # end foreach QP
      foreach my $QP ( $Quote->Products() ) {
        my $NewQP = $QP->copy();
        $variable{error} .= $NewQP->save({quote_id=>$NewQuote->id()});
      } # end foreach QP

      my %by;
      openprint::quote::get_user_by_info( $log, $dbh, \%by, $Quote->id() );
      $NewQuote->store_user_by_info( \%by );
      if ( $Quote->company_id() == $NewQuote->company_id() ) {
        my %for;
        openprint::quote::get_user_for_info( $log, $dbh, \%for, $Quote->id() );
        $NewQuote->store_user_for_info( \%for );
      } # end if
      $NewQuote->add_log( 'Copied from quote ' . $Quote->id() );
      $Quote->add_log( 'Copied to quote ' . $NewQuote->id() );
      $quote_id = $NewQuote->id();
      $variable{ExternalRedirect} = '/main/quote/information.html?quote_id='.$quote_id;
      return;
    } elsif (($param{btnFunction} eq 'Continue') or $param{remove} ) {
      $quote_id = $param{quote_id};
      # this should only happen if there was an error creating the quote

      my $Quote = $variable{Quote} = new openprint::Quote( $quote_id );  
      $session{quote_id} = $quote_id;

      if ( $param{remove} ) {
        sql::execute($log, $dbh, 'DELETE FROM tbl_Quote_Details WHERE quote_id=? AND project_id=?', @param{'quote_id','remove'} );
        $Quote->add_log( 'Remove project ' . $param{remove} );
      } # end if

      # store fields from recalculate, we only store the markup, the NewPrices will calculate on the fly
      foreach my $key ( keys %param ) {
        foreach my $QP ( $Quote->Quoted_Projects() ) {
          foreach my $qty_index ( $QP->quantity_indexes() ) {
            $QP->markup($qty_index, $param{'markup-'.$qty_index.'_'.$QP->project_id()});
            $QP->quantity($qty_index, undef);
            # setting markup will recalc price, but should really take the price as seen on screen due to rounding errors
            $QP->price($qty_index, $param{'price-'.$qty_index.'_'.$QP->project_id()});  
          } # end foreach
          $QP->description($QP->Project()->reference());
          $QP->save();
        } # end foreach
      } # end foreach
    } # end if
  } # end if btnFunction

	$quote_id = ( $param{quote_id} ? $param{quote_id} : $session{quote_id} ) if !$quote_id;
	my $Quote = $variable{Quote} = new openprint::Quote( $quote_id );  

  my $populated = 0;
  if ( ! openprint::quote::get_user_for_info( $log, $dbh, \%variable, $quote_id ) ) {
    foreach my $k ( 'CompanyName','Address1','Address2','City','StateProvince','PostalCode','Country','Phone','Extension','Fax','FirstName','LastName','Title','Email','Salutation' ) {
      if ( $session{'/main/quote/information.html?For'.$k} ) {
        $variable{'For'.$k} = $session{'/main/quote/information.html?For'.$k};
        $populated = 1;
      } # end if
    } # end foreach

    if ( $session{user_id} and ! $populated ) {
      # If we are representing some other company
      if ( $$openprint::User{company_id} != $session{company_id} ) {
        my $Company = $openprint::Company;
# pull information to pre-fill input fields
				@variable{'ForCompanyName', 'ForAddress1', 'ForAddress2', 'ForCity', 'ForStateProvince', 'ForPostalCode', 'ForCountry', 'ForPhone','ForExtension', 'ForFax' } = (
        $Company->business_name(), $Company->address1(), $Company->address2(), $Company->city(), $Company->state(), $Company->postalcode(), $Company->country(), $Company->phone(), $Company->extension(), $Company->fax() );

        my @Users = openprint::User->find(company_id=>$openprint::session{company_id}, limit=>2);
        if ( @Users == 1 ) {
          @variable{'ForFirstName','ForLastName','ForTitle','ForEmail','ForSalutation'} = $Users[0]->get('firstname','lastname','title','email','salutation');
        } # end if
			} # end if
		} # end if
	} # end if

	if ( ! openprint::quote::get_user_by_info( $log, $dbh, \%variable, $quote_id ) ) {
		if ( $session{user_id} ) {
# pull information to pre-fill input fields
			my $Company = $openprint::User->Company();
			@variable{'ByCompanyName', 'ByAddress1', 'ByAddress2', 'ByCity', 'ByStateProvince', 'ByPostalCode', 'ByCountry', 'ByPhone', 'ByExtension', 'ByFax'} = $Company->get('business_name','address1','address2','city','state','postalcode','country','phone','extension','fax' );
		} # end if
	} # end if

	if ( ! $variable{ByEmail} ) {
		if ( $session{user_id} ) {
			@variable{'ByEmail','ByTitle','ByFirstName','ByLastName','BySalutation'} = $openprint::User->get('email','title','firstname','lastname','salutation');
		} # end if
	} # end if

  if ( $quote_id ) {
    openprint::quote::get_unfinished_quote_contents( $log, $dbh, \%variable, $quote_id );
  } # end if
} # end sub information

sub submit {
  if ( %param ) {
    foreach my $k ( 'CompanyName','Address1','Address2','City','StateProvince','PostalCode','Country','Phone','Extension','Fax','FirstName','LastName','Title','Email','Salutation' ) {
      $session{'/main/quote/information.html?For'.$k} = $param{'For'.$k} if exists $param{'For'.$k};
    } # end foreach
  } # end if

  my $quote_id = $param{quote_id};
  $quote_id = $session{quote_id} if !$quote_id;
  my $Quote = $variable{Quote} = new openprint::Quote($quote_id);
  $Quote->save() if ! $Quote->id();
  $session{quote_id} = $Quote->id();

  if ( $param{btnFunction} eq 'SendToMe' ) {
    if ( $Quote->can_view( ) ) {
      my $results = $Quote->send($openprint::User);
      $variable{information} .= 'Quote Sent To Me. Results: '. $results;
    } else {
      $variable{error} .= q`Can't send quote. You are not allowed to view it.<br/>`;
    } # end if
    $variable{ExternalRedirect} = '/main/quote/submit.html?quote_id='.$Quote->id();
    return;
  } elsif ( $param{btnFunction} eq 'Continue' ) {
    my %by;
    my %for;
    foreach my $key ( %param ) {
      if ( $key =~ /^By/ ) {
        $by{$key} = $param{$key};
      } elsif ( $key =~ /^For/ ) {
        $for{$key} = $param{$key};
      } # end if
    } # end foreach

    my @required_fields = split(',', $config{QuoteRequiredFields});

    my $error = '';
    $error .= 'No prepared by first name entered.<br>' if $param{ByFirstName} eq '' and sets::isin('ByFirstName', \@required_fields );
    $error .= 'No prepared by last name entered.<br>' if $param{ByLastName} eq '' and sets::isin('ByLastName', \@required_fields );
    $error .= 'No prepared by email address entered.<br>' if $param{ByEmail} eq '' and sets::isin('ByEmail', \@required_fields );
    if ( $error ne '' ) {
      return misc::error($log, $dbh, \%variable, 'Error', $error);
    } # end if

    if ( $param{ForFirstName} or $param{ForLastName} or $param{ForEmail} ) {
      my $error = '';
      $error .= 'No prepared for email address entered.<br>' if $param{ForEmail} eq '' and sets::isin('ForEmail', \@required_fields );
      if ( $error ne '' ) {
        return misc::error( $log, $dbh, \%variable, 'Error', $error );
      } # end if

    } else {
      foreach my $key ( keys %by ) {
        $key =~ /By(.*)/;
        $for{'For'.$1} = $by{$key};
      } # end foreach
    } # end if

    $Quote->save({
        for_company_id=>$param{for_company_id},
        reference=>$param{reference},
        comments=>$param{comments},
        status=>'Incomplete',
        currency_id=>$param{currency_id},
        });
    $Quote->store_user_by_info( \%by );
    $Quote->store_user_for_info( \%for );
# store fields from recalculate, we only store the markup, the NewPrices will calculate on the fly
    # On submit, if all is well, we set final costs, nothing should change after this, unless we go back to information
    foreach my $QP ( $Quote->Quoted_Projects() ) {
      foreach my $qty_index ( $QP->quantity_indexes() ) {
        $QP->markup($qty_index, $param{'markup-'.$qty_index.'_'.$QP->project_id()});
        $QP->quantity($qty_index, undef);
        $QP->price($qty_index, $param{'price-'.$qty_index.'_'.$QP->project_id()});
      } # end foreach
      $QP->description($QP->Project()->reference());
      $QP->save();
    } # end foreach
    foreach my $QP ( $Quote->Products() ) {
        $variable{error} .= $QP->save({
            cost      => $param{'cost-'.$QP->id()},
            markup    => $param{'markup-'.$QP->id()},
            quantity  => $param{'quantity-'.$QP->id()},
            units  => $param{'units-'.$QP->id()},
            comments  => $param{'comments-'.$QP->id()},
        });
    } # end foreach
    $variable{ExternalRedirect} = '/main/quote/submit.html?quote_id='.$Quote->id();
    return;
  } # end if btnFunction eq Continue

  if ( sets::isin( $session{user_type}, [ 'A', 'E' ] ) ) {
    $variable{AdministratorName} = new openprint::User( $session{user_id} )->name();
  } # end if

  openprint::quote::get_unfinished_quote_contents( $log, $dbh, \%variable, $quote_id );

} # end submit

sub confirmation {

	my $quote_id = $param{quote_id};
  $quote_id = $session{quote_id} if !$quote_id;
  my $Quote = new openprint::Quote($quote_id);
  $variable{Quote} = $Quote;
  if ( !$$Quote{id} ) {
    if ( $quote_id ) {
      $variable{error} .= 'Quote ' . $quote_id . ' not found.<br/>';
    } else {
      $variable{error} .= 'No incomplete quote to send.<br/>';
    } # end if
    return;
  } # end if

	if ( $param{btnFunction} eq 'Close' ) {
    if ( $Quote->status() ne 'Complete' ) {

      my @subtotals;

      my $warning = '';
      foreach my $QP ( $Quote->Quoted_Projects() ) {
        foreach my $qty_index ( $QP->quantity_indexes() ) {
          my $old_price = $QP->price($qty_index);
          if ( $old_price != $QP->price($qty_index,undef) ) {
            $warning .= 'Price change from '.$Quote->Currency()->format($old_price). ' to ' . $Quote->Currency()->format($QP->price($qty_index)).' for project '.$QP->Project()->id().' quantity ' . $qty_index.'<br/>';
          }
          my $old_quantity = $QP->quantity($qty_index);
          if ( $old_quantity != $QP->quantity($qty_index,undef) ) {
            $warning .= "Price change from $old_quantity to " . $QP->quantity($qty_index).' for project '.$QP->Project()->id().' quantity ' . $qty_index.'<br/>';
          }
          $subtotals[$qty_index] += $QP->price($qty_index);
        } # end foreach
        $QP->save();
      } # end foreach QP
      foreach my $Product ( $Quote->Products() ) {
        $Product->save({cost=>$Product->cost()});
        $subtotals[1] += $Product->price();
        $subtotals[2] += $Product->price();
        $subtotals[3] += $Product->price();
      } # end foreach Product
      foreach my $qty_index ( 1 .. 3 ) {
        $Quote->total($qty_index, $subtotals[$qty_index]);
      } # end foreach
      $Quote->administrator_name($param{AdministratorName}) if exists $param{AdministratorName};
      $Quote->administrator_comments($param{AdministratorComments}) if exists $param{AdministratorComments};
      if ( $warning ) {
        $Quote->save();
        $variable{warning} = $warning.'<br/>Please verify the quoted prices/quantities and click Submit again.';
        $variable{ExternalRedirect} = '/main/quote/submit.html?quote_id='.$Quote->id();
      } else {
        $Quote->status('Complete');
        $Quote->save();
        $Quote->send();
        $Quote->add_log('Submitted');
      }
    } else {
      $variable{error} .= 'This quote has already been sent.  Not sending again.<br/>';
    } # end if ! Complete
		$Quote->status('Complete');
		$Quote->save();
		$Quote->add_log('Closed');
	} elsif ( $param{btnFunction} eq 'Submit' ) {

		if ( $Quote->status() ne 'Complete' ) {

			my @subtotals;

			my $warning = '';
			foreach my $QP ( $Quote->Quoted_Projects() ) {
				foreach my $qty_index ( $QP->quantity_indexes() ) {
					my $old_price = $QP->price($qty_index);
					if ( $old_price != $QP->price($qty_index,undef) ) {
						$warning .= 'Price change from '.$Quote->Currency()->format($old_price). ' to ' . $Quote->Currency()->format($QP->price($qty_index)).' for project '.$QP->Project()->id().' quantity ' . $qty_index.'<br/>';
					}
					my $old_quantity = $QP->quantity($qty_index);
					if ( $old_quantity != $QP->quantity($qty_index,undef) ) {
						$warning .= "Price change from $old_quantity to " . $QP->quantity($qty_index).' for project '.$QP->Project()->id().' quantity ' . $qty_index.'<br/>';
					}
					$subtotals[$qty_index] += $QP->price($qty_index);
				} # end foreach
				$QP->save();
			} # end foreach QP
			foreach my $Product ( $Quote->Products() ) {
				$Product->save({cost=>$Product->cost()});
				$subtotals[1] += $Product->price();
				$subtotals[2] += $Product->price();
				$subtotals[3] += $Product->price();
			} # end foreach Product
			foreach my $qty_index ( 1 .. 3 ) {
				$Quote->total($qty_index, $subtotals[$qty_index]);
			} # end foreach
			$Quote->administrator_name($param{AdministratorName}) if exists $param{AdministratorName};
			$Quote->administrator_comments($param{AdministratorComments}) if exists $param{AdministratorComments};
			if ( $warning ) {
				$Quote->save();
				$variable{warning} = $warning.'<br/>Please verify the quoted prices/quantities and click Submit again.';
				$variable{ExternalRedirect} = '/main/quote/submit.html?quote_id='.$Quote->id();
			} else {
				$Quote->status('Complete');
				$Quote->save();
				$Quote->send();
				$Quote->add_log('Submitted');
			}
		} else {
			$variable{error} .= 'This quote has already been sent.  Not sending again.<br/>';
		} # end if ! Complete
	} else {
		$log->error("Unknown function in quote confirmation $param{btnFunction}");
	} # end if action
  delete $session{quote_id};
} # end sub finalise_quote

sub _project_template {
  $variable{Quote} = new openprint::Quote( $param{quote_id} );
  $variable{QuotedProject} = new openprint::QuotedProject( $param{project_id} );
  $variable{QuotedProject}->include_detailed( $param{include_detailed} );
  $variable{QuotedProject}->save();
} # end sub _project_template

sub _project_template_view {
  $variable{Quote} = new openprint::Quote( $param{quote_id} );
  $variable{QuotedProject} = new openprint::QuotedProject( $param{project_id} );
  $variable{QuotedProject}->template_id( $param{template_id} );
  $variable{QuotedProject}->save();
  $variable{Project} = $variable{QuotedProject}->Project();
  $variable{ProjectIndex} = $variable{Project}->id();
} # end sub _project_template

sub _quote_list {
} # end sub _quote_list

sub _view_log {
} # end sub _view_log

sub _products {
  $variable{Quote} = new openprint::Quote( $param{quote_id} );
  if ( ! $variable{Quote} ) {
    $variable{error} .= "Empty or invalid quote specified.";
    return;
  } # end if

  if ( $param{action} ) {
    foreach my $Product ( $variable{Quote}->Products() ) {
      $variable{error} .= $Product->save({
          'quantity'    =>  $param{'quantity-'.$Product->id()},
          'markup'    =>  $param{'markup-'.$Product->id()},
          'units'    =>  $param{'units-'.$Product->id()},
          });
    } # end foreach
    if ( $param{action} eq 'add' ) {
      my $Product = new openprint::QuotedProduct();
      $variable{error} .= $Product->save({
          'quote_id'    =>  $param{quote_id},
          'product_id'  =>  $param{'product_id-'},
          'quantity'    =>  $param{'quantity-'},
          'cost'      =>  $param{'cost-'},
          'markup'    =>  $param{'markup-'},
          'units'    =>  $param{'units-'},
          });
    } elsif ( $param{action} eq 'del' ) {
      my $Product = new openprint::QuotedProduct( $param{product_id} );
      $variable{error} .= $Product->delete();
      delete $variable{Quote}{Products};
    } # end if
  } # end if
} # end sub _products

sub overview {
} # end sub overview

sub _quote_list {
} # end sub _quote_list

sub _products_dropdown {
} # end sub _products_dropdown

sub _view_log {
} # end sub _view_log

sub _user_information {
} # end sub _user_information

sub _company_information {
} # end sub _company_information

1;

__END__
