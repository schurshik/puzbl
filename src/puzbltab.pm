package puzbltab;

# PUZBL #---
# puzbltab.pm #---
# Developer: Branitskiy Alexander <schurshick@yahoo.com> #---
use Gtk2 '-init';
use Glib qw /TRUE FALSE/;
use feature qw /state/;
use constant DEFAULT_TAB => "puzbl";
use constant TAB_MAXLEN => 10;

sub new
{
    my $class = shift;
    state $counter = 0;
    my $self = { SOCK => Gtk2::Socket->new(),
                 HBOX => Gtk2::HBox->new(FALSE, 0),
		 EVENTBOX => Gtk2::EventBox->new(),
                 LABEL => Gtk2::Label->new(DEFAULT_TAB),
		 BUTTON => new Gtk2::Button,
                 PID => undef,
                 NAME => sprintf("%d_%d", $$, $counter++),
                 CLIENT => undef,
		 URL => undef,
		 # enable or disable status bar
		 ENABLESTATUSBAR => TRUE };
    $self->{EVENTBOX}->set_events('button_press_mask');
    $self->{EVENTBOX}->add($self->{LABEL});
    $self->{HBOX}->pack_start($self->{EVENTBOX}, FALSE, FALSE, 0);
    $self->{BUTTON}->add(Gtk2::Image->new_from_stock('gtk-close', 'button'));
    $self->{BUTTON}->set_relief('none');
    $self->{BUTTON}->set_focus_on_click(FALSE);
    $self->{HBOX}->pack_end($self->{BUTTON}, FALSE, FALSE, 0);
    $self->{HBOX}->show_all();
    bless $self, $class;
    return $self;
}

sub run #(SOCKNAME, URL, TITLE)
{
    my $self = shift;
    my $args = shift;
    my $socket_name = (defined $args && defined $args->{SOCKNAME}) ? $args->{SOCKNAME} : undef;
    my $url = (defined $args && defined $args->{URL}) ? $args->{URL} : undef;
    my $title = (defined $args && defined $args->{TITLE}) ? $args->{TITLE} : DEFAULT_TAB;
    $self->set_tabname($title);
    my $command = "uzbl-browser -n " . $self->{NAME} . " -s " . $self->{SOCK}->get_id() . " --connect-socket $socket_name";
    $command .= " --uri '$url'" if (defined $url);
    my $pid = fork();
    if ($pid == 0)
    {
        exec($command);
	exit 0;
    }
    else
    {
        $self->{PID} = $pid;
    }
}

sub back
{
    my $self = shift;
    send($self->{CLIENT}, "back\n", 0) if ($self->{CLIENT});
}

sub forward
{
    my $self = shift;
    send($self->{CLIENT}, "forward\n", 0) if ($self->{CLIENT});
}

sub reload
{
    my $self = shift;
    send($self->{CLIENT}, "reload\n", 0) if ($self->{CLIENT});
}

sub uri
{
    my $self = shift;
    my $uri = shift;
    send($self->{CLIENT}, "uri $uri\n", 0) if ($self->{CLIENT});
}

sub statusbar
{
    my $self = shift;
    send($self->{CLIENT}, "toggle_status\n", 0) if ($self->{CLIENT});
}

sub set_url
{
    my $self = shift;
    $self->{URL} = shift;
}

sub get_url
{
    my $self = shift;
    return (defined $self->{URL}) ? $self->{URL} : "";
}

sub exit
{
    my $self = shift;
    if (defined($self->{CLIENT}))
    {
	send($self->{CLIENT}, "exit\n", 0);
        waitpid($self->{PID}, 0);
        close $self->{CLIENT};
    }
}

sub set_tabname
{
    my $self = shift;
    my $tabname = shift;
    $self->{LABEL}->set_text($tabname) if (defined $tabname);
    my @text = split "", $tabname;
    if (scalar(@text) > TAB_MAXLEN)
    {
	my $dots = "...";
	$tabname = (join "", @text[0..TAB_MAXLEN - length($dots) - 1]) . $dots;
    }
    else
    {
	$tabname .= (" " x (TAB_MAXLEN - scalar(@text)));
    }
    $self->{LABEL}->set_markup("<span foreground=\"blue\" size=\"medium\"><tt><b>$tabname</b></tt></span>") if (defined $tabname);
}

sub get_tabname
{
    my $self = shift;
    return (defined $self->{LABEL}) ? $self->{LABEL}->get_text() : "";
}

sub set_client
{
    my $self = shift;
    my $client = shift;
    $self->{CLIENT} = $client if (defined $client);
}

1; #---
