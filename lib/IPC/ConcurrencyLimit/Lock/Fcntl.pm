package IPC::ConcurrencyLimit::Lock::Fcntl;
use 5.008001;
use strict;
use warnings;
use Carp qw(croak);
use File::Path qw();
use File::Spec;
use Fcntl qw(:DEFAULT);
use File::FcntlLock;
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

  my $fs = File::FcntlLock->new(
    l_type   => $self->{lock_mode} eq 'shared' ? F_RDLCK : F_WRLCK,
    l_whence => SEEK_SET,
    l_start  => 0,
    l_len    => 0,
  );

  for my $worker (1 .. $self->{max_procs}) {
    my $lock_file = File::Spec->catfile($self->{path}, "$worker.lock");

    sysopen(my $fh, $lock_file, O_RDWR|O_CREAT)
      or die "can't open '$lock_file': $!";

    if ($fs->lock($fh, F_SETLK)) {
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

IPC::ConcurrencyLimit::Lock::Fcntl- fcntl() based locking

=head1 SYNOPSIS

  use IPC::ConcurrencyLimit;

=head1 DESCRIPTION

This locking strategy implements C<fcntl()> based concurrency control.
Requires that your system has a sane C<fcntl()> implementation as well
as a non-blocking C<fcntl()> mode.

Inherits from L<IPC::LimitConcurrency::Lock>.

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

Beaware of one disadvantage of C<fcnt()> type of locks: a lock is lost if ANY file descriptor referring to a file on which locks are held is closed. Excerpt from C<man fcntl>:

    As well as being removed by an explicit F_UNLCK, record locks are automatically released when the process terminates or if it closes ANY file descriptor referring to a file on which locks are held.
    This is bad: it means that a process can lose the locks on a file like /etc/passwd or /etc/mtab when for some reason a library function decides to open, read and close it.

It means that you should not open/close lock files inside the proccess which holds the locks. For more details consult to C<man fcntl>.

If this strategy is not sutiable for you consider using flock backend.

=head1 AUTHOR

Ivan Kruglov, C<ivan.kruglov@yahoo.com>

Steffen Mueller, C<smueller@cpan.org>

Yves Orton

=head1 ACKNOWLEDGMENT

This module was originally developed for booking.com.
With approval from booking.com, this module was generalized
and put on CPAN, for which the authors would like to express
their gratitude.

=head1 COPYRIGHT AND LICENSE

 (C) 2011, 2012, 2013 Steffen Mueller. All rights reserved.
 
 This code is available under the same license as Perl version
 5.8.1 or higher.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

=cut

