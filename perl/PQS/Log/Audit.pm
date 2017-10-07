package PQS::Log::Audit;
use strict;
use warnings;

use Apache2::Cookie      ();
use Apache2::Const qw(:common :http);
use Apache2::Util      qw(ht_time);
use PQS::DB             ();
use session;

sub handler {
    my $r = shift; # The current request.

    # We need to log every change (POST) that didn't error out.
    my @req;
    push @req, $r if $r->method eq 'POST' and $r->status != SERVER_ERROR;
        
    # There may be a number of internal/external redirects operating across
    # the whole request. If the current request isn't the initial one, we'll
    # have to backtrack to get them all.
    unless ($r->is_initial_req) {
        while (my $r = $r->prev) {
            push @req, $r
                if $r->method eq 'POST' and $r->status != SERVER_ERROR; 
        }
    }
    # We're only interest in successful changes.
    return DECLINED unless scalar @req;
    
    # Grab our database for logging.
    my $dbh = PQS::DB->connect($r) or return DECLINED;

    session::r($r);
    session::log($r->log);
    session::dbh($dbh);

    # Instead of storing each time a user modifies something, we're keeping an
    # aggregate count of the number of times a user modifies a specific
    # section (as determined by the query string) from a specific location.
   
    # Check if the user has done anything to this page today.
    my $exist = $dbh->prepare_cached(q{
        SELECT id FROM audit_log 
        WHERE date = ? AND login = ? AND ip = ? AND page = ? AND query = ?
    });
    
    # For every sucessful change we check to see if the user has already
    # changed that instance today, if so we just update the aggregate count.
    foreach my $req (@req) {
        my %logline = %{ gather($req, $dbh) };

        my $id = scalar $dbh->selectrow_array(
            $exist, undef, @logline{qw( date login ip page query )});

        if ( $id ) { # If the record exists, up it's count.
            my $update = $dbh->prepare_cached(q{
                UPDATE audit_log SET hits = hits + 1 WHERE id = ? });
            $update->execute($id);
        }
        else { # Otherwise insert it.
            my $insert = $dbh->prepare_cached(q{
                INSERT INTO audit_log ("date", "user", login, ip, page, query)
                VALUES (?, ?, ?, ?, ?, ?) });
            $insert->execute( @logline{qw( date user login ip page query )} );
        }
    };
    $dbh->commit;
    
    return OK;
}


# Gather the needed logging information from the given request.
sub gather {
    my $r   = shift;
    my $dbh = shift;
    
    # As we're auditting through time, we'll get both the user's unique ID
    # and their unique login. As either may change or be deleted. To get that
    # info we'll have to trace them from their session.
    my ($user, $login);
    { 
        my $session  = (Apache2::Cookie->fetch)->{SessionID}->value;
        my $customer = $dbh->prepare_cached(q{
            SELECT lnguserid, stremail 
            FROM tbl_logged_in 
            WHERE chrsite      IN ( 'A', 'E')
              AND strsessionid = ?
        });
        ($user, $login) = $dbh->selectrow_array($customer, undef, $session);
    }

    # Gather the needed information.
    my %logline = (
        date   => ht_time($r->request_time, '%Y-%m-%d'),
        user   => $user,
        login  => $login,
        ip     => $r->connection->remote_ip,
        page   => $r->uri,
        query  => $r->args || q{},
    );

    return \%logline;
}

### TABLE STRUCTURE
#
# BEGIN;
# 
# CREATE TABLE audit_log (
#     id SERIAL PRIMARY KEY, -- Surrogate key.
#     "date" DATE,
#     "user" INT NOT NULL REFERENCES tbl_customer_users(lnguserid)
#         ON UPDATE CASCADE    -- The user's ID, this can change or be NULL if
#         ON DELETE SET NULL,  -- user is deleted. Login is for unchanging data.
#     login TEXT NOT NULL, -- User's login (email) at the time of auditting.
#     ip    INET NOT NULL, -- Accessing IP.
#     page  TEXT NOT NULL, -- Requested page.
#     query TEXT NOT NULL DEFAULT '',  -- Query string (empty is valid)
#     hits  INT NOT NULL DEFAULT 1,
#     UNIQUE ("date", login, ip, page, query)
# ) WITHOUT OIDS;
# COMMENT ON TABLE audit_log
#     IS 'An aggregate count of the changes to customer data through the interface. Logged accessed page.';
# 
# COMMIT;
# 
#
1;
