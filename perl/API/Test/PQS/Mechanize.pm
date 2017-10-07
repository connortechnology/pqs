package Test::PQS::Mechanize;
use strict;
use warnings;

use Test::Builder;
my $Test = Test::Builder->new;

use base qw(Test::WWW::Mechanize Exporter);

our @EXPORT = qw(try);

# Login credentials.
use constant {
    USERNAME => 'tester@print-quotes-software.com',
    PASSWORD => 'F1#$~my',
};

our $site = $ENV{PQS_TEST_SITE}
         || 'http://bahama.dev.print-quotes-software.com';

sub new {
    my ($class, %args) = @_;

    %args = (%args, 
        agent      => 'PQS Automated Testing',
        cookie_jar => {},
        # autocheck => 1,
    );

    return $class->SUPER::new(%args);
}
sub login_api{
    my ($self, $user, $pass, $url) = @_;

    # We can find the site?
    $self->SUPER::get_ok($url, {}, 'find site');

    $self->form_name('f1');
    $self->field(txtEmail    => $user);
    $self->field(txtPassword => $pass);
    $self->submit;

print STDERR "LOGIN SITE: $url - $user -- $pass \n";
    # Make sure we've logged in correctly.
    $self->content_contains('Welcome', 'login');

    return $self;
}

sub login_ok {
    my ($self) = @_;

    # We can find the site?
    $self->SUPER::get_ok($site, {}, 'find site');

    $self->form_name('f1');
    $self->field(txtEmail    => USERNAME);
    $self->field(txtPassword => PASSWORD);
    $self->submit;


    # Make sure we've logged in correctly.
    $self->content_contains('Welcome', 'login');

    return $self;
}

sub fill_form {
    my ($self, $data) = @_;

    while (my ($field, $info) = each %$data) {
        my ($type, $value) = @$info{qw(type value)};

        if ($type =~ /^select/) {
            $self->select($field, $value);
        }
        elsif ($type eq 'checkbox') {
            $value = [ $value ] if !ref $value;
            $self->tick($field, $_) for @$value;
        }
        else {
            die "Single field (field) has multiple values."
                if ref $value;

            $self->field($field, $value);
        }
    }

    return $self;
}

sub get_ok {
    my ($self, $url, $args, $name) = @_;

    $self->SUPER::get_ok("${site}$url", $args, $name);
}

sub create_ok {
    my ($self, $url, $args, $name) = @_;

    $self->SUPER::get_ok("$url", $args, $name);
}


sub submit_ok {
    my ($self, $form, $fields, $name) = @_;

    eval { $self->form_name($form) };
    if ($@) {
        $Test->ok(0, $name);
        $Test->diag($@);
        return 0;
    }

    eval { $self->fill_form($fields) };
    if ($@) {
        $Test->ok(0, $name);
        $Test->diag($@);
        return 0;
    }
    
    # TODO Check return of this?
    $self->click();

    # TODO Check $self->status?

    $Test->ok(1, $name);

    return 1;
}


# # Class method
# sub try (&@) {
#     my ($func, $mech, $msg) = @_;
# 
#     die "Second argument to submit must be a mechanize object."
#         unless ref $mech && ref $mech eq __PACKAGE__;
# 
#     local $_ = $mech;
# 
#     eval { $func->() };
# 
#     $Test->ok(!$@, $msg);
#     $Test->diag($@);
# 
#     return 1;
# }
 

1;
