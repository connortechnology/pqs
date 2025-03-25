package openprint::logUser;

use strict;

sub new
{
   my ($class) = @_;
   my $self = {
      _id  => undef,
      _firstName => undef,
      _lastName => undef,
      _email => undef,
   };
   bless $self, $class;
   return $self;
}

################################################################################
# subroutine name: id
# purpose: Used to request or assign the logUser's user id.
# usage: $logRecord->id('1');
# parameters: 1 - (Scalar - Int) User ID.
#
# return: (Scalar - Int) logUser's _id value.
sub id
{
   my ( $self, $id ) = @_;
   $self->{_id} = $id if defined($id);
   return $self->{_id};
}

################################################################################
# subroutine name: firstName
# purpose: Used to request or assign the logUser's first name.
# usage: $logRecord->firstName('Bob');
# parameters: 1 - (Scalar - String) User's first name.
#
# return: (Scalar - String) logUser's _firstName value.
sub firstName
{
   my ( $self, $firstName ) = @_;
   $self->{_firstName} = $firstName if defined($firstName);
   return $self->{_firstName};
}

################################################################################
# subroutine name: lastName
# purpose: Used to request or assign the logUser's last name.
# usage: $logRecord->lastName('Smith');
# parameters: 1 - (Scalar - String) User's last name.
#
# return: (Scalar - String) logUser's _lastName value.
sub lastName
{
   my ( $self, $lastName ) = @_;
   $self->{_lastName} = $lastName if defined($lastName);
   return $self->{_lastName};
}

################################################################################
# subroutine name: email
# purpose: Used to request or assign the logUser's email.
# usage: $logRecord->email('bob.smith@google.com');
# parameters: 1 - (Scalar - String) User's last name.
#
# return: (Scalar - String) logUser's _email value.
sub email
{
   my ( $self, $email ) = @_;
   $self->{_email} = $email if defined($email);
   return $self->{_email};
}

return 1;
