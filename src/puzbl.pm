package puzbl;

# PUZBL #---
# puzbl.pm #---
# Developer: Branitskiy Alexander <schurshick@yahoo.com> #---
use puzbltab; #---
use Gtk2 '-init';
use Gtk2::Helper;
use Gtk2::Gdk::Keysyms;
use Glib qw(TRUE FALSE);
use Socket qw(PF_UNIX SOCK_STREAM SOMAXCONN sockaddr_un);
use POSIX qw(mkfifo ceil);
use Fcntl qw(O_RDWR O_EXCL O_CREAT O_RDONLY O_NONBLOCK);
use Encode qw(is_utf8 decode_utf8);
use constant DATA_LEN => 1024;
use constant PUZBL_DIR => $ENV{"HOME"} . (($ENV{"HOME"} =~ m:/$:) ? "" : "/") . ".puzbl/";
use constant GTKRC_FILE => $ENV{"HOME"} . (($ENV{"HOME"} =~ m:/$:) ? "" : "/") . ".puzbl/gtkrc";
use constant URLS_FILE => $ENV{"HOME"} . (($ENV{"HOME"} =~ m:/$:) ? "" : "/") . ".puzbl/urls";
use constant CONFIG_FILE => $ENV{"HOME"} . (($ENV{"HOME"} =~ m:/$:) ? "" : "/") . ".puzbl/config";
use constant TABS_FILE => $ENV{"HOME"} . (($ENV{"HOME"} =~ m:/$:) ? "" : "/") . ".puzbl/tabs";
use constant HOME_PAGE => "https://google.com";

sub new
{
    my $class = shift;
    my $self = { # main window
                 WINDOW => undef,
		 # vertical box
		 VBOX => undef,
		 # text field
		 ENTRY => undef,
                 # list of puzbl tabs
                 PUZBLTABS => [],
                 # index of an active puzbl tab
                 PUZBLTABIND => -1,
                 # notebook with tabs
                 NOTEBOOK => undef,
                 # name of socket file
                 SNAME => "/tmp/puzbl_" . $$ . ".socket",
                 # socket for communicating with tabs
                 SOCKET => undef,
                 # name of fifo file
                 FNAME => "/tmp/puzbl_" . $$ . ".fifo",
                 # fifo for communicating with tabs
                 FIFO => undef,
		 # event watch object
		 WATCHER => undef,
		 # state of left ctrl key (false when it is released; true when it is pressed)
		 PRESSCTRLL => FALSE,
		 # state of left alt key (false when it is released; true when it is pressed)
		 PRESSALTL => FALSE,
		 # state of left shift key (false when it is released; true when it is pressed)
		 PRESSSHFTL => FALSE,
		 # check menu of `save tabs`
		 MENUSAVTABS => undef,
		 # check menu of status bar
		 MENUSTBAR => undef,
		 # check menu of `show buttons`
		 MENUSHOWBUTT => undef,
		 # hbox with buttons
		 HBOXBUTT => undef };
    bless $self, $class;
    return $self;
}

sub run
{
    my $self = shift;
    my $urls = (defined $_[0]) ? shift : undef;
    $self->create_app();
    $self->create_socket();
    $self->create_fifo();
    $self->create_puzbltabs($urls);
    Gtk2->main();
}

sub create_config
{
    mkdir(PUZBL_DIR, 0755) unless (-d PUZBL_DIR);
    if ((-d PUZBL_DIR) && (not(-e GTKRC_FILE) || (-z GTKRC_FILE)))
    {
	open my $file_desc, ">", GTKRC_FILE;
	print $file_desc <<EOF;
gtk-icon-sizes = "panel-menu=14,14:panel=14,14:gtk-large-toolbar=14,14:gtk-small-toolbar=14,14:gtk-button=14,14"
style "button" = "default"
{
  xthickness = 0
  ythickness = 0
}
style "default"
{
  xthickness = 0
  ythickness = 0
  GtkNotebook::tab-border = 0
  GtkNotebook::tab-hborder = 0
  GtkNotebook::tab-vborder = 0
  GtkNotebook::show-border = 0
  GtkNotebook::gtk-button-images = 0
  GtkNotebook::gtk-menu-images = 0
  GtkNotebook::arrow-spacing = 0
  GtkNotebook::tab-curvature = 0
  GtkNotebook::tab-overlap = 0
  GtkNotebook::focus-line-width = 0
  GTKButton::min-button-size = 5
  GtkRange::trough_border = 0
  GtkRange::slider_width = 10
}
style "font"
{
  font_name = "Corbel 10"
}
widget_class "*" style "font"
gtk-font-name = "Corbel 10"
gtk-icon-theme-name = "KFaenza"
gtk-theme-name = "Murrine-Gray"
gtk-font-name = "DejaVu Sans 3"
EOF
        close $file_desc;
    }
    if ((-d PUZBL_DIR) && (not(-e CONFIG_FILE) || (-z CONFIG_FILE)))
    {
        my @arr = ("menu", "buttons");
        my $is_enabled = TRUE;
        open my $file_desc, ">", CONFIG_FILE;
        foreach (@arr)
        {
	    print $file_desc "$_ = " . (($is_enabled == TRUE) ? "enable" : "disable") . "\n";
	}
        close $file_desc;
    }
    if ((-d PUZBL_DIR) && not(-e URLS_FILE))
    {
        my @arr = ("https://www.google.com", "https://www.github.com", "https://www.yahoo.com", "http://www.uzbl.org");
        open my $file_desc, ">", URLS_FILE;
        foreach (@arr)
        {
	    print $file_desc "$_\n";
	}
        close $file_desc;
    }
    if ((-d PUZBL_DIR) && not(-e TABS_FILE))
    {
        my $file_desc;
        sysopen($file_desc, TABS_FILE, O_RDWR|O_EXCL|O_CREAT, 0644) and close($file_desc);
    }
    Gtk2::Rc->parse(GTKRC_FILE) if -e GTKRC_FILE;
}

sub create_app
{
    my $self = shift;
    $self->create_config();
    $self->create_vbox();
    $self->create_menubar();
    $self->create_buttons();
    $self->create_notebook();
    $self->create_window();
}

sub create_socket
{
    my $self = shift;
    socket(my $socket, PF_UNIX, SOCK_STREAM, 0) || die "Error socket: $!";
    unlink $self->{SNAME};
    bind($socket, sockaddr_un($self->{SNAME})) || die "Error bind: $!";
    listen($socket, SOMAXCONN);
    $self->{SOCKET} = $socket;
    Gtk2::Helper->add_watch(fileno($socket), 'in', sub { read_socket($self); });
}

sub create_fifo
{
    my $self = shift;
    unlink $self->{FNAME};
    mkfifo($self->{FNAME}, 0744) || die "mkfifo failed: $!";
    sysopen(my $fifo, $self->{FNAME}, O_RDONLY | O_NONBLOCK) || die "error open: $!";
    $self->{FIFO} = $fifo;
    my $watcher;
    $watcher = Gtk2::Helper->add_watch(fileno($fifo), 'in', sub { read_fifo($self, $watcher); });
}

sub create_puzbltabs
{
    my $self = shift;
    my $urls = (defined $_[0]) ? shift : undef;
    if (defined($urls) && (ref($urls) eq 'ARRAY') && scalar(@{$urls}) > 0)
    {
	foreach (@{$urls})
	{
	    $self->add_tab({URL => $_});
	}
    }
    elsif (-e TABS_FILE)
    {
	my $file_desc;
	open $file_desc, TABS_FILE;
	while (my $tab = <$file_desc>)
	{
	    next if ($tab =~ m/^\s*#+/);
	    chomp $tab;
	    $self->add_tab({URL => $tab});
	}
	close $file_desc;
    }
    $self->add_tab() if (scalar(@{$self->{PUZBLTABS}}) == 0);
}

sub create_vbox
{
    my $self = shift;
    $self->{VBOX} = Gtk2::VBox->new(FALSE, 0);
}

sub create_submenu_file
{
    my $self = shift;
    my $submenu = Gtk2::Menu->new();
    $submenu->append(Gtk2::SeparatorMenuItem->new());
    my $create_imagemenuitem_func = sub { my ($name, $image, $action) = (@_);
					  ref($action) eq 'CODE' or die "Error: the last argument must be a function $!";
					  my $elem = Gtk2::ImageMenuItem->new($name);
					  $elem->set_image(Gtk2::Image->new_from_stock($image, 'button'));
					  $elem->signal_connect('activate' => $action);
					  $submenu->append($elem); };
    &$create_imagemenuitem_func("Back uri", 'gtk-go-back', sub { $self->back_uri(); });
    &$create_imagemenuitem_func("Forward uri", 'gtk-go-forward', sub { $self->forward_uri(); });
    &$create_imagemenuitem_func("Add tab", 'gtk-add', sub { $self->add_tab(); });
    &$create_imagemenuitem_func("Close tab", 'gtk-remove', sub { $self->del_tab(); });
    &$create_imagemenuitem_func("Reload page", 'gtk-refresh', sub { $self->reload_uri(); });
    &$create_imagemenuitem_func("Stop loading", 'gtk-stop', sub { $self->stop_loading(); });
    &$create_imagemenuitem_func("Save page", 'gtk-save', sub { $self->save_page(); });
    &$create_imagemenuitem_func("Home page", 'gtk-home', sub { $self->new_uri(HOME_PAGE); });
    &$create_imagemenuitem_func("Quit", 'gtk-quit', sub { $self->exit(); });
    $submenu->append(Gtk2::SeparatorMenuItem->new());
    return $submenu;
}

sub create_submenu_settings
{
    my $self = shift;
    my $submenu = Gtk2::Menu->new();
    $submenu->append(Gtk2::SeparatorMenuItem->new());
    my $create_menuitem_func = sub { my ($name, $active, $action) = (@_);
				     ref($action) eq 'CODE' or die "Error: the last argument must be a function $!";
				     my $menuitem = Gtk2::CheckMenuItem->new($name);
				     $menuitem->set_active($active);
				     $menuitem->signal_connect('toggled' => $action);
				     $submenu->append($menuitem);
				     return $menuitem; };
    $self->{MENUSAVTABS} = &$create_menuitem_func("Save tabs", TRUE, sub { ; });
    $self->{MENUSTBAR} = &$create_menuitem_func("Status bar", TRUE, sub { if (${$self->{PUZBLTABS}}[$self->{PUZBLTABIND}]->{ENABLESTATUSBAR} != $self->{MENUSTBAR}->get_active()) {
	${$self->{PUZBLTABS}}[$self->{PUZBLTABIND}]->statusbar(); } });
    $self->{MENUSHOWBUTT} = &$create_menuitem_func("Show buttons", TRUE, sub { if ($self->{MENUSHOWBUTT}->get_active() == TRUE) { $self->{HBOXBUTT}->show_all(); } else { $self->{HBOXBUTT}->hide_all(); } });
    $submenu->append(Gtk2::SeparatorMenuItem->new());
    return $submenu;
}

sub create_submenu_help
{
    my $self = shift;
    my $submenu = Gtk2::Menu->new();
    $submenu->append(Gtk2::SeparatorMenuItem->new());
    my $create_menuitem_func = sub { my ($title, $image, $message) =  @_;
				     my $menu_item = Gtk2::MenuItem->new($title);
				     $menu_item->signal_connect('activate' => sub { my $dialog = Gtk2::MessageDialog->new ($self->{WINDOW},
															   ['modal', 'destroy-with-parent'],
															   $image, # message type
															   'close', # which set of buttons?
															   $message);
										    $dialog->run();
										    $dialog->destroy(); });
				     $submenu->append($menu_item); };
    &$create_menuitem_func("Info", 'info', "PUZBL - frontend interface to uzbl\nbrowser written on Perl + Gtk 2");
    &$create_menuitem_func("About", 'question', "PUZBL\nDeveloper: Branitskiy Alexander\nVersion: 1.0.0");
    $submenu->append(Gtk2::SeparatorMenuItem->new());
    return $submenu;
}

sub read_config
{
    my %hash_config;
    if (-e CONFIG_FILE)
    {
	open my $file_desc, CONFIG_FILE;
	while (my $line = <$file_desc>)
	{
	    next if ($line =~ m/^\s*#+/);
	    if ($line =~ m/^\s*([^\s]*)\s*=\s*([^\s]*)$/)
	    {
		my ($elem, $value) = ($1, $2);
		if (($elem eq "menu" || $elem eq "buttons") &&
		    ($value eq "enable" || $value eq "disable"))
		{
		    $hash_config{$elem} = ($value eq "disable") ? FALSE : TRUE;
		}
	    }
	}
	close $file_desc;
    }
    return %hash_config;
}

sub create_menubar
{
    my $self = shift;
    my $hbox = new Gtk2::HBox(FALSE, 0);
    $hbox->set_spacing(0);
    my %hash_config = $self->read_config();
    unless (exists($hash_config{"menu"}) && $hash_config{"menu"} == FALSE)
    {
	my $menu_bar = Gtk2::MenuBar->new();
	my $menu_item_file = Gtk2::MenuItem->new("File");
	$menu_item_file->set_submenu($self->create_submenu_file());
	my $menu_item_settings = Gtk2::MenuItem->new("Settings");
	$menu_item_settings->set_submenu($self->create_submenu_settings());
	$menu_item_settings->signal_connect('activate' => sub { $self->{MENUSTBAR}->set_active(${$self->{PUZBLTABS}}[$self->{PUZBLTABIND}]->{ENABLESTATUSBAR}); });
	my $menu_item_help = Gtk2::MenuItem->new("Help");
	$menu_item_help->set_submenu($self->create_submenu_help());
	$menu_bar->append($menu_item_file);
	$menu_bar->append($menu_item_settings);
	$menu_bar->append($menu_item_help);
	my $hbox_menu_bar = new Gtk2::HBox(FALSE, 0);
	$hbox_menu_bar->set_spacing(0);
	$hbox_menu_bar->pack_start($menu_bar, FALSE, FALSE, 0);
	$hbox->pack_start($hbox_menu_bar, FALSE, FALSE, 0);
    }
    my $hbox_label = new Gtk2::HBox(TRUE, 0);
    my $label = new Gtk2::Label;
    $label->set_markup("<span foreground=\"red\" size=\"x-large\"><tt><b><u>PUZBL</u></b></tt></span>");
    $hbox_label->pack_start($label, TRUE, TRUE, 0);
    my $event_box = new Gtk2::EventBox;
    $event_box->signal_connect('button-press-event' => sub { $self->new_uri("https://github.com/schurshik/puzbl"); });
    $event_box->add($hbox_label);
    $hbox->pack_start($event_box, TRUE, TRUE, 0);
    my $frame = Gtk2::Frame->new();
    $frame->add($hbox);
    $self->{VBOX}->pack_start($frame, FALSE, FALSE, 0);
}

sub create_buttons
{
    my $self = shift;
    my $hbox = new Gtk2::HBox(FALSE, 0);
    $hbox->set_spacing(0);
    my $hbox_buttons = new Gtk2::HBox(FALSE, 0);
    $hbox_buttons->set_spacing(0);
    my $create_button_func = sub { my ($image, $action) = (@_);
				   ref($action) eq 'CODE' or die "Error: the last argument must be a function $!";
				   my $button = new Gtk2::Button;
				   $button->signal_connect('clicked' => $action);
				   $button->add(Gtk2::Image->new_from_stock($image, 'button'));
				   $hbox_buttons->pack_start($button, FALSE, FALSE, 0); };
    &$create_button_func('gtk-go-back', sub { $self->back_uri(); });
    &$create_button_func('gtk-go-forward', sub { $self->forward_uri(); });
    &$create_button_func('gtk-add', sub { $self->add_tab(); });
    &$create_button_func('gtk-remove', sub { $self->del_tab(); });
    &$create_button_func('gtk-refresh', sub { $self->reload_uri(); });
    &$create_button_func('gtk-stop', sub { $self->stop_loading(); });
    &$create_button_func('gtk-save', sub { $self->save_page(); });
    &$create_button_func('gtk-home', sub { $self->new_uri(HOME_PAGE); });
    &$create_button_func('gtk-quit', sub { $self->exit(); });
    $self->{HBOXBUTT} = $hbox_buttons;
    $hbox->pack_start($hbox_buttons, FALSE, FALSE, 0);
    my $hbox_entry = new Gtk2::HBox(TRUE, 0);
    my $entry = new Gtk2::Entry;
    $entry->signal_connect('activate' => sub { $self->new_uri($entry->get_text()); });
    $hbox_entry->pack_start($entry, TRUE, TRUE, 0);
    $self->{ENTRY} = $entry;
    $hbox->pack_start($hbox_entry, TRUE, TRUE, 0);
    my $frame = Gtk2::Frame->new();
    $frame->add($hbox);
    $self->{VBOX}->pack_start($frame, FALSE, FALSE, 0);
}

# go to the previous url
sub back_uri
{
    my ($self, $index) = @_;
    $index = $self->{PUZBLTABIND} unless (defined $index);
    ${$self->{PUZBLTABS}}[$index]->back();
}

# go to the next url
sub forward_uri
{
    my ($self, $index) = @_;
    $index = $self->{PUZBLTABIND} unless (defined $index);
    ${$self->{PUZBLTABS}}[$index]->forward();
}

# refresh url
sub reload_uri
{
    my ($self, $index) = @_;
    $index = $self->{PUZBLTABIND} unless (defined $index);
    ${$self->{PUZBLTABS}}[$index]->reload();
}

# stop loading the page
sub stop_loading
{
    my $self = shift;
    ${$self->{PUZBLTABS}}[$self->{PUZBLTABIND}]->stop();
}

# save page
sub save_page
{
    my ($self, $index) = @_;
    $index = $self->{PUZBLTABIND} unless (defined $index);
    ${$self->{PUZBLTABS}}[$index]->save(PUZBL_DIR);
}

# change url
sub new_uri
{
    my ($self, $uri, $index) = @_;
    $index = $self->{PUZBLTABIND} unless (defined $index);
    ${$self->{PUZBLTABS}}[$index]->uri($uri);
}

sub create_frameuri
{
    my $self = shift;
    my $uri = shift;
    my $frame = Gtk2::Frame->new();
    $frame->set_shadow_type('out');
    my $event_box = Gtk2::EventBox->new;
    $event_box->set_events(['button_press_mask', 'enter_notify_mask']);
    $event_box->signal_connect('button-press-event' => sub { $self->add_tab({URL => $uri}); });
    $event_box->set_events('enter_notify_mask');
    $event_box->signal_connect('enter_notify_event' => sub { $frame->set_shadow_type('in'); });
    $event_box->signal_connect('leave_notify_event' => sub { $frame->set_shadow_type('out'); });
    $event_box->add(Gtk2::Label->new($uri));
    $frame->add($event_box);
    return $frame;
}

sub create_addtab
{
    my $self = shift;
    my $vbox = Gtk2::VBox->new(TRUE, 0);
    my $hbox = undef;
    if (-e URLS_FILE)
    {
	my $file_desc;
	open $file_desc, URLS_FILE;
	my @array_uri;
	while (my $uri = <$file_desc>)
	{
	    push(@array_uri, $uri) unless ($uri =~ m/^\s*#+/);
	}
	close $file_desc;
	my $dim = ceil(sqrt(scalar(@array_uri)));
	for (my $i = 0; $i < scalar(@array_uri); ++$i)
	{
	    if ($i % $dim == 0)
	    {
		$hbox = Gtk2::HBox->new(TRUE, 0);
	    }
	    $hbox->pack_start($self->create_frameuri($array_uri[$i]), TRUE, TRUE, $dim);
	    if ($i % $dim == $dim - 1 || $i == $#array_uri)
	    {
		$vbox->pack_start($hbox, TRUE, TRUE, $dim);
	    }
	}
    }
    my $event_box = Gtk2::EventBox->new;
    $self->{NOTEBOOK}->append_page($event_box, Gtk2::Image->new_from_stock('gtk-add', 'button'));
    $event_box->add($vbox);
    $event_box->show_all();
    $self->{NOTEBOOK}->set_tab_reorderable($event_box, FALSE);
}

sub create_notebook
{
    my $self = shift;
    my $notebook = Gtk2::Notebook->new();
    $notebook->set_scrollable(TRUE);
    $notebook->set_tab_pos('top');
    $notebook->signal_connect('switch-page', \&switch_page, $self);
    $notebook->signal_connect('page-reordered', \&reorder_page, $self);
    $self->{VBOX}->pack_start($notebook, TRUE, TRUE, 0);
    $self->{NOTEBOOK} = $notebook;
    $self->create_addtab();
}

sub create_window
{
    my $self = shift;
    my $window = Gtk2::Window->new('toplevel');
    $window->set_default_size(640, 480);
    $window->set_position('center_always');
    $window->set_border_width(5);
    $window->add($self->{VBOX});
    $window->show_all();
    my %hash_config = $self->read_config();
    $self->{MENUSHOWBUTT}->set_active((exists($hash_config{"buttons"}) && $hash_config{"buttons"} == FALSE) ? FALSE : TRUE);
    $window->signal_connect('delete-event' => sub { $self->exit; });
    $window->signal_connect('key-press-event', \&key_press, $self);
    $window->signal_connect('key-release-event', \&key_release, $self);
    $self->{WINDOW} = $window;
}

sub key_press
{
    # the first parameter is a widget
    my (undef, $event, $self) = @_;
    foreach my $key (keys %Gtk2::Gdk::Keysyms)
    {
	if ($Gtk2::Gdk::Keysyms{$key} == $event->keyval())
	{
	    if ($key eq "Control_L")
	    {
		$self->{PRESSCTRLL} = TRUE;
	    }
	    elsif ($key eq "Alt_L")
	    {
		$self->{PRESSALTL} = TRUE;
	    }
	    elsif ($key eq "Shift_L")
	    {
		$self->{PRESSSHFTL} = TRUE;
	    }
	    if (($event->get_state() & qw(control-mask)) && $self->{PRESSCTRLL} == TRUE)
	    {
		if ($key eq "t")
		{
		    $self->add_tab();
		}
		elsif ($key eq "w")
		{
		    $self->del_tab();
		}
		elsif ($key eq "l")
		{
		    $self->entry_select();
		}
	    }
	    elsif (($event->get_state() & qw(mod1-mask)) && $self->{PRESSALTL} == TRUE)
	    {
		if ($key =~ m/^[1-9]{1}$/)
		{
		    $self->goto_tab($key - 1);
		}
	    }
	    elsif (($event->get_state() & qw(shift-mask)) && $self->{PRESSSHFTL} == TRUE)
	    {
		if ($key eq "Left")
		{
		    $self->prev_tab();
		}
		elsif ($key eq "Right")
		{
		    $self->next_tab();
		}
	    }
	    last;
	}
    }
}

sub key_release
{
    my (undef, $event, $self) = @_;
    foreach my $key (keys %Gtk2::Gdk::Keysyms)
    {
	if ($Gtk2::Gdk::Keysyms{$key} == $event->keyval())
	{
	    if ($key eq "Control_L")
	    {
		$self->{PRESSCTRLL} = FALSE;
	    }
	    elsif ($key eq "Alt_L")
	    {
		$self->{PRESSALTL} = FALSE;
	    }
	    elsif ($key eq "Shift_L")
	    {
		$self->{PRESSSHFTL} = FALSE;
	    }
	    last;
	}
    }
}

# add new tab to the tab list
sub add_tab #(URL, TITLE, SWITCH, NEXT)
{
    my $self = shift;
    my $args = (defined $_[0]) ? shift : undef;
    my $url = (defined $args && defined $args->{URL}) ? $args->{URL} : undef;
    my $title = (defined $args && defined $args->{TITLE}) ? $args->{TITLE} : undef;
    my $switch = (defined $args && defined $args->{SWITCH}) ? $args->{SWITCH} : TRUE;
    my $next = (defined $args && defined $args->{NEXT}) ? $args->{NEXT} : FALSE;
    my $puzbltab_obj = puzbltab->new();
    $puzbltab_obj->{EVENTBOX}->signal_connect('button-press-event', \&button_press, [$self, $puzbltab_obj]);
    my $new_pos = ($next == TRUE) ? $self->{PUZBLTABIND} + 1 : scalar(@{$self->{PUZBLTABS}});
    $self->{NOTEBOOK}->insert_page($puzbltab_obj->{SOCK}, $puzbltab_obj->{HBOX}, $new_pos);
    $self->{NOTEBOOK}->set_tab_reorderable($puzbltab_obj->{SOCK}, TRUE);
    $puzbltab_obj->run({SOCKNAME => $self->{SNAME}, URL => $url, TITLE => $title});
    $self->{NOTEBOOK}->show_all();
    $self->ins_puzbltab($puzbltab_obj, $new_pos);
    if ($switch)
    {
	$self->{NOTEBOOK}->set_current_page($new_pos);
	$self->{PUZBLTABIND} = $new_pos;
    }
    $puzbltab_obj->{BUTTON}->signal_connect('clicked' => sub { my (undef, $index) = get_puzbltab($self, $puzbltab_obj->{NAME});
							       $self->del_tab($index) if (defined $index); });
}

sub entry_select
{
    my $self = shift;
    $self->{ENTRY}->grab_focus();
}

sub entry_text
{
    my ($self, $name, $text) = @_;
    my ($puzbltab_obj) = $self->get_puzbltab($name);
    if (defined $puzbltab_obj)
    {
	$puzbltab_obj->set_url($text);
	if (${$self->{PUZBLTABS}}[$self->{PUZBLTABIND}]->{NAME} eq $name)
	{
	    $self->{ENTRY}->set_text($text);
	}
    }
}

sub button_press
{
    my ($widget, $event, $ref) = @_;
    my ($self, $puzbltab_obj) = @{$ref};
    if ($event->button == 3)
    {
	my (undef, $index) = $self->get_puzbltab($puzbltab_obj->{NAME});
	$self->del_tab($index);
        #$self->create_submenu_file()->popup(undef, undef, undef, undef, 0, 0);
    }
}

# go to the tab with indicated number
sub goto_tab
{
    my $self = shift;
    my $new_pos = shift;
    if ($new_pos < scalar(@{$self->{PUZBLTABS}}))
    {
        $self->{NOTEBOOK}->set_current_page($new_pos);
        $self->{PUZBLTABIND} = $new_pos;
    }
}

# go to the next tab
sub next_tab
{
    my $self = shift;
    my $new_pos = ($self->{PUZBLTABIND} + 1) % scalar(@{$self->{PUZBLTABS}});
    $self->goto_tab($new_pos);
}

# go to the previous tab
sub prev_tab
{
    my $self = shift;
    my $new_pos = ($self->{PUZBLTABIND} == 0) ? $#{$self->{PUZBLTABS}} : $self->{PUZBLTABIND} - 1;
    $self->goto_tab($new_pos);
}

# go to the first tab
sub first_tab
{
    my $self = shift;
    $self->goto_tab(0);
}

# go to the last tab
sub last_tab
{
    my $self = shift;
    $self->goto_tab($#{$self->{PUZBLTABS}});
}

# preset command
sub preset_command
{
    my ($self, $args) = @_;
    # TODO: contunue...
}

# close all active tabs and open a new tab
sub clean_tabs
{
    my $self = shift;
    $self->del_tabs();
    $self->add_tab();
}


# insert new puzbl object to the array with indicated position
sub ins_puzbltab
{
    my ($self, $puzbl_obj, $in_pos) = @_;
    push(@{$self->{PUZBLTABS}}, undef);
    for (my $i = $#{$self->{PUZBLTABS}} - 1; $i >= $in_pos; --$i)
    {
	${$self->{PUZBLTABS}}[$i + 1] = ${$self->{PUZBLTABS}}[$i];
    }
    ${$self->{PUZBLTABS}}[$in_pos] = $puzbl_obj;
}

# delete tab with indicated number
sub del_tab
{
    my $self = shift;
    my $tab_number = (defined $_[0]) ? shift : $self->{PUZBLTABIND};
    if ($tab_number < scalar(@{$self->{PUZBLTABS}}))
    {
        $self->{NOTEBOOK}->remove_page($tab_number);
        $self->destroy_puzbltab($tab_number);
        my $puzbltabs = \@{$self->{PUZBLTABS}};
        for ($tab_number..$#{$puzbltabs} - 1)
        {
            ${$puzbltabs}[$_] = ${$puzbltabs}[$_ + 1];
        }
        pop @{$puzbltabs};
        if (scalar(@{$puzbltabs}))
        {
            $self->{PUZBLTABIND} = $self->{NOTEBOOK}->get_current_page();
        }
        else
        {
            $self->exit();
        }
    }
}

# get puzbltab object and its index by its name
sub get_puzbltab
{
    my $self = shift;
    my $name = shift;
    for my $index (0..$#{$self->{PUZBLTABS}})
    {
	return (${$self->{PUZBLTABS}}[$index], $index) if (${$self->{PUZBLTABS}}[$index]->{NAME} eq $name);
    }
    return undef;
}

sub change_window_title
{
    my $self = shift;
    my $title = "puzbl <" . ${$self->{PUZBLTABS}}[$self->{PUZBLTABIND}]->get_tabname() . ">";
    $self->{WINDOW}->set_title($title);
}

sub set_tabname
{
    my ($self, $name, $title) = @_;
    my ($puzbltab_obj) = $self->get_puzbltab($name);
    if (defined $puzbltab_obj)
    {
	$puzbltab_obj->set_tabname((Encode::is_utf8 $title) ? $title : Encode::decode_utf8($title));
	$self->change_window_title();
    }
}

sub set_client
{
    my ($self, $name, $client) = @_;
    my ($puzbltab_obj) = $self->get_puzbltab($name);
    $puzbltab_obj->set_client($client) if (defined $puzbltab_obj);
}

sub exit
{
    my $self = shift;
    $self->destroy_puzbltabs();
    $self->destroy_fifo();
    $self->destroy_socket();
    $self->destroy_app();
}

sub destroy_puzbltabs
{
    my $self = shift;
    if (-e TABS_FILE)
    {
	my $file_desc;
	open $file_desc, ">", TABS_FILE;
	if (!defined($self->{MENUSAVTABS}) || $self->{MENUSAVTABS}->get_active() == TRUE)
	{
	    foreach my $puzbltab (@{$self->{PUZBLTABS}})
	    {
		print $file_desc ($puzbltab->{URL} . "\n") if (defined $puzbltab->{URL});
	    }
	}
	close $file_desc;
    }
    $self->del_tabs();
}

sub del_tabs
{
    my $self = shift;
    foreach (0..$#{$self->{PUZBLTABS}})
    {
        $self->destroy_puzbltab($_);
    }
}

sub destroy_puzbltab
{
    my $self = shift;
    my $index = (defined $_[0]) ? shift : $self->{PUZBLTABIND};
    ${$self->{PUZBLTABS}}[$index]->exit() if ($index < scalar(@{$self->{PUZBLTABS}}));
}

sub destroy_fifo
{
    my $self = shift;
    close $self->{FIFO};
    unlink($self->{FNAME});
}

sub destroy_socket
{
    my $self = shift;
    close $self->{SOCKET};
    unlink($self->{SNAME});
}

sub destroy_app
{
    Gtk2->main_quit();
}

sub switch_page
{
    my $switch_pos = $_[2];
    my $self = $_[3];
    if (defined ${$self->{PUZBLTABS}}[$switch_pos])
    {
	$self->{PUZBLTABIND} = $switch_pos;
	my $url = ${$self->{PUZBLTABS}}[$switch_pos]->get_url();
	$self->{ENTRY}->set_text($url) if defined $url;
	$self->change_window_title();
    }
}

sub reorder_page
{
    my $new_pos = $_[2]; # to position
    my $self = $_[3];
    my $old_pos = $self->{PUZBLTABIND}; # from position
    my $puzbltab_list = \@{$self->{PUZBLTABS}};
    if ($new_pos == $self->{NOTEBOOK}->get_n_pages() - 1)
    {
	$self->{NOTEBOOK}->reorder_child($self->{NOTEBOOK}->get_nth_page($new_pos), $old_pos);
	return;
    }
    # tab moves right
    if ($new_pos > $old_pos)
    {
        my $active_puzbltab_obj = ${$puzbltab_list}[$old_pos];
        for ($old_pos..$new_pos - 1)
        {
            ${$puzbltab_list}[$_] = ${$puzbltab_list}[$_ + 1];
        }
        ${$puzbltab_list}[$new_pos] = $active_puzbltab_obj;
    }
    # tab moves left
    else
    {
        my $active_puzbltab_obj = ${$puzbltab_list}[$old_pos];
        for (my $i = $old_pos; $i > $new_pos; --$i)
        {
            ${$puzbltab_list}[$i] = ${$puzbltab_list}[$i - 1];
        }
        ${$puzbltab_list}[$new_pos] = $active_puzbltab_obj;
    }
    $self->{PUZBLTABIND} = $new_pos;
}

sub change_enable_statusbar
{
    my ($self, $enable) = @_;
    ${$self->{PUZBLTABS}}[$self->{PUZBLTABIND}]->{ENABLESTATUSBAR} = $enable;
}

sub read_fifo
{
    my $self = shift;
    my $watcher = shift;
    my $fifo = $self->{FIFO};
    my $data;
    if (not sysread($fifo, $data, DATA_LEN))
    {
	Gtk2::Helper->remove_watch($watcher) || die "error removing watcher";
	close $fifo;
	return TRUE;
    }
    return TRUE unless (defined $data);
    chomp $data;
    my @cmd = split " ", $data;
    if ($cmd[0] eq "add")
    {
        if (defined $cmd[1])
        {
	    $self->add_tab({URL => $cmd[1]});
        }
        else
        {
            $self->add_tab();
        }
    }
    elsif ($cmd[0] eq "del")
    {
        if (defined $cmd[1])
        {
            $self->del_tab($cmd[1]);
        }
        else
        {
            $self->del_tab();
        }
    }
    elsif ($cmd[0] eq "url")
    {
	if (defined $cmd[1])
	{
	    $self->new_uri($cmd[1]);
	}
    }
    elsif ($cmd[0] eq "goto")
    {
	if (defined $cmd[1])
	{
	    $self->goto_tab($cmd[1]);
	}
    }
    elsif ($cmd[0] eq "prev")
    {
	$self->prev_tab();
    }
    elsif ($cmd[0] eq "next")
    {
	$self->next_tab();
    }
    elsif ($cmd[0] eq "first")
    {
	$self->first_tab();
    }
    elsif ($cmd[0] eq "last")
    {
	$self->last_tab();
    }
    return TRUE;
}

sub read_socket
{
    my $self = shift;
    accept(my $client, $self->{SOCKET});
    $self->{WATCHER} = Glib::IO->add_watch(fileno($client), ['in', 'hup'], \&read_data, [$client, $self]);
    return TRUE;
}

sub read_data
{
    my (undef, $condition, $ref) = @_;
    my ($client, $self) = @{$ref};
    my $client_data;
    if ((not defined $client) || ($condition eq 'hup') || (not sysread($client, $client_data, DATA_LEN)))
    {
	Gtk2::Helper->remove_watch($self->{WATCHER}) || die "Error remove watch: $!";
	close $client if (defined $client);
	return FALSE;
    }
    return FALSE unless (defined $client_data);
    foreach my $data (split "\n", $client_data)
    {
	if ($data =~ /EVENT \[(.+)\] (.*)/)
	{
	    my $name = $1;
	    my ($type, $args) = split " ", $2, 2;
	    next unless defined $type;
	    # gn
	    # go <url>
	    if ($type eq "NEW_TAB")
	    {
		$self->add_tab({URL => $args});
	    }
	    elsif ($type eq "NEW_BG_TAB")
	    {
		$self->add_tab({URL => $args, SWITCH => FALSE});
	    }
	    # gO
	    elsif ($type eq "NEW_TAB_NEXT")
	    {
		$self->add_tab({URL => $args, NEXT => TRUE});
	    }
	    elsif ($type eq "NEW_BG_TAB_NEXT")
	    {
		$self->add_tab({URL => $args, SWITCH => FALSE, NEXT => TRUE});
	    }
	    # gt
	    elsif ($type eq "NEXT_TAB")
	    {
		$self->next_tab();
	    }
	    # gT
	    elsif ($type eq "PREV_TAB")
	    {
		$self->prev_tab();
	    }
	    # gi
	    elsif ($type eq "GOTO_TAB")
	    {
		$self->goto_tab($args);
	    }
	    # g<
	    elsif ($type eq "FIRST_TAB")
	    {
		$self->first_tab();
	    }
	    # g>
	    elsif ($type eq "LAST_TAB")
	    {
		$self->last_tab();
	    }
	    elsif ($type eq "PRESET_TABS")
	    {
		$self->preset_command($args);
	    }
	    elsif ($type eq "BRING_TO_FRONT")
	    {
		$self->{WINDOW}->present();
	    }
	    # gQ
	    elsif ($type eq "CLEAN_TABS")
	    {
		$self->clean_tabs();
	    }
	    elsif ($type eq "EXIT_ALL_TABS")
	    {
		$self->del_tabs();
	    }
	    elsif ($type eq "VARIABLE_SET")
	    {
		if (defined $args && $args =~ /^uri str ('.+')$/)
		{
		    print "";
		}
		elsif (defined $args && $args =~ /^show_status int ([01])$/)
		{
		    $self->change_enable_statusbar(($1 == 0) ? FALSE : TRUE);
		}
	    }
	    elsif ($type eq "TITLE_CHANGED")
	    {
		$self->set_tabname($name, ($args =~ s/^'(.+)'$/$1/) ? $args : $args);
	    }
	    # gC
	    elsif ($type eq "COMMAND_EXECUTED")
	    {
		if (defined $args && $args eq "exit ")
		{
		    $self->del_tab();
		}
		elsif (defined $args && $args eq "toggle_status ")
		{
		    $self->change_enable_statusbar($self->{MENUSTBAR}->get_active());
		}
	    }
	    elsif ($type eq "INSTANCE_START")
	    {
		$self->set_client($name, $client);
	    }
	    elsif ($type eq "LOAD_PROGRESS")
	    {
		$self->{ENTRY}->set_progress_fraction(($args / 100 == 1) ? 0 : $args / 100);
	    }
	    elsif ($type eq "LOAD_FINISH")
	    {
		$self->entry_text($name, ($args =~ s/^'(.+)'$/$1/) ? $args : $args);
	    }
	}
    }
    return TRUE;
}

1; #---
