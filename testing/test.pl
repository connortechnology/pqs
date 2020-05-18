use strict;
use warnings;

use Email::Sender::Simple qw(sendmail);
use Email::Sender::Transport::SMTP::TLS ();
use Email::Sender::Transport::SMTPS ();
use Email::Simple ();
use Email::Simple::Creator ();

my $smtpserver = 'smtpa.bellnet.ca';
my $smtpport = 465;
my $smtpuser   = 'manoj1234';
my $smtppassword = 'Ca64533A';

my $transport = Email::Sender::Transport::SMTP::TLS->new({
  host => $smtpserver,
  port => $smtpport,
  username => $smtpuser,
  password => $smtppassword,
  helo => 'pqsdev.sherwoodprinters.com'
});

my $transport1 = Email::Sender::Transport::SMTPS->new({
  host => $smtpserver,
  port => $smtpport,
  ssl  => 'ssl',
  sasl_username => $smtpuser,
  sasl_password => $smtppassword,
  helo => 'pqsdev.sherwoodprinters.com',
  debug => 1
});

my $email = Email::Simple->create(
  header => [
    To      => 'wcober@gmail.com',
    From    => 'info@sherwoodprinters.com',
    #From    => 'manoj@bellnet.ca',
    Subject => 'Hi!',
  ],
  body => "This is my message\n",
);

sendmail($email, { transport => $transport1 });
