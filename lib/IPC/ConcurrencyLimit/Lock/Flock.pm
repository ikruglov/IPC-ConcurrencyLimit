package IPC::ConcurrencyLimit::Lock::Flock;
use 5.008001;
use strict;
use warnings;
use Carp qw(croak);
use File::Path qw();
use File::Spec;
use Fcntl qw(:DEFAULT :flock);
use IO::File ();

use IPC::ConcurrencyLimit::Lock;
our @ISA = qw(IPC::ConcurrencyLimit::Lock);

sub new {
  my $class = shift;
  my $opt = shift;

  my $max_procs = $opt->{max_procs}
    or croak("Need a 'max_procs' parameter");
  my $path = $opt->{path}
    or croak("Need a 'path' parameter");
  my $lock_mode = lc($opt->{lock_mode} || 'exclusive');
  if ($lock_mode !~ /^(?:exclusive|shared)$/) {
    croak("Invalid lock mode '$lock_mode'");
  }

  my $self = bless {
    max_procs => $max_procs,
    path      => $path,
    lock_fh   => undef,
    lock_file => undef,
    id        => undef,
    lock_mode => $lock_mode,
  } => $class;

  $self->_get_lock() or return undef;

  return $self;
}

sub _get_lock {
  my $self = shift;

  File::Path::mkpath($self->{path});
  my $lock_mode_flag = $self->{lock_mode} eq 'shared' ? LOCK_SH : LOCK_EX;

  for my $worker (1 .. $self->{max_procs}) {
    my $lock_file = File::Spec->catfile($self->{path}, "$worker.lock");

    sysopen(my $fh, $lock_file, O_RDWR|O_CREAT)
      or die "can't open '$lock_file': $!";

    if (flock($fh, $lock_mode_flag|LOCK_NB)) {
      $self->{lock_fh} = $fh;
      seek($fh, 0, 0);
      truncate($fh, 0);
      print $fh $$;
      $fh->flush;
      $self->{id} = $worker;
      $self->{lock_file} = $lock_file;
      last;
    }

    close $fh;
  }

  return undef if not $self->{id};
  return 1;
}

sub lock_file { $_[0]->{lock_file} }
sub path { $_[0]->{path} }

sub DESTROY {
  my $self = shift;
  # should be superfluous
  close($self->{lock_fh}) if $self->{lock_fh};
}

1;

__END__


=head1 NAME

IPC::ConcurrencyLimit::Lock::Flock - flock() based locking

=head1 SYNOPSIS

  use IPC::ConcurrencyLimit;

=head1 DESCRIPTION

This locking strategy implements C<flock()> based concurrency control.
Requires that your system has a sane C<flock()> implementation as well
as a non-blocking C<flock()> mode.

Inherits from L<IPC::LimitConcurrency::Lock>.

Take care not to attempt to use this on an NFS share or any other file
system that does not implement atomic C<flock()>!

=head1 METHODS

=head2 new

Given a hash ref with options, attempts to obtain a lock in
the pool. On success, returns the lock object, otherwise undef.

Required options:

=over 2

=item C<path>

The directory that will hold the lock files.
Created if it does not exist.
It is suggested not to use a directory that may hold other data.

=item C<max_procs>

The maximum no. of locks (and thus usually processes)
to allow at one time.

=back

Other options:

=over 2

=item C<lock_mode>

Defaults to C<exclusive> locks.

In particular circumstance, you might want to set this to C<shared>.
This subverts the way the normal concurrency limit works, but allows
entirely different use cases.

=back

=head2 lock_file

Returns the full path and name of the lock file.

=head2 path

Returns the directory in which the lock files resides.

=head1 NOTES

Be aware of that C<flock()> locks are preserved across C<fork()>. It means that if after acquiring a lock a process does C<fork()>, it will share the lock with the child. And if the parent happens to die, the lock will be still in place. For more details consult to C<man flock>.

If this strategy is not sutiable for you consider using fcntl backend.

=head1 AUTHOR

Steffen Mueller, C<smueller@cpan.org>

Yves Orton

=head1 ACKNOWLEDGMENT

This module was originally developed for booking.com.
With approval from booking.com, this module was generalized
and put on CPAN, for which the authors would like to express
their gratitude.

=head1 COPYRIGHT AND LICENSE

 (C) 2011, 2012 Steffen Mueller. All rights reserved.
 
 This code is available under the same license as Perl version
 5.8.1 or higher.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

=cut

