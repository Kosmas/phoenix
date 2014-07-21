defmodule Phoenix.Controller do
  import Phoenix.Controller.Connection
  import Plug.Conn
  alias Plug.MIME
  alias Phoenix.Plugs

  @default_content_type "text/html"
  @plug_default_mime_type "application/octet-stream"

  @moduledoc """
  Phoenix Controllers are responsible for handling the dispatch of Router requests

  Like Routers, Controllers are Plugs, but contain a required :action plug that
  is implicitly added to the end plug chain. The :action proxies to the function
  defined in the Router. The :action plug can be explicitly added to change
  its execution order.

  ## Examples

      defmodule MyApp.Controllers.Admin.Users do
        use Phoenix.Controller

        plug :authenticate, usernames: ["jose", "eric", "sonny"]

        def authenticate(conn, options) do
          if get_session(conn, username) in options[:usernames] do
            conn
          else
            conn |> redirect(Router.root_path) |> halt!
          end
        end

        def show(conn, params) do
          # authenticated users only
        end
      end

  """
  defmacro __using__(options) do
    quote do
      import Plug.Conn
      import Phoenix.Controller.Connection
      import unquote(__MODULE__)
      @options unquote(options)

      @subview_module view_module(__MODULE__)
      @layout_module layout_module(__MODULE__)

      def init(options), do: options
      @before_compile unquote(__MODULE__)
      use Phoenix.Plugs.Builder
      unless @options[:bare] do
        plug Plugs.ParamsFetcher
        plug Plugs.ContentTypeFetcher
      end
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      unless Plugs.plugged?(@plugs, :action) do
        plug :action
      end

      def action(conn, _options) do
        apply(__MODULE__, conn.private[:phoenix_action], [conn, conn.params])
      end

      def render(conn, template, assigns \\ []) do
        render_view conn, @subview_module, @layout_module, template, assigns
      end
    end
  end

  @doc """
  Carries out Controller action after successful Router match, invoking the
  "2nd layer" Plug stack.

  Connection query string parameters are fetched automatically before
  controller actions are called, as well as merging any named parameters from
  the route definition.
  """
  def perform_action(conn, controller, action, named_params) do
    conn = assign_private(conn, :phoenix_named_params, named_params)
    |> assign_private(:phoenix_action, action)
    |> assign_private(:phoenix_controller, controller)

    apply(controller, :call, [conn, []])
  end

  @doc """
  Sends 404 not found response to client
  """
  def not_found(conn, method, path) do
    text conn, :not_found, "No route matches #{method} to #{inspect path}"
  end

  def error(conn, error) do
    status = Plug.Exception.status(error)

    html conn, status, """
      <html>
        <body>
          <pre>Something went wrong</pre>
        </body>
      </html>
    """
  end

  @doc """
  Render HTML response with stack trace for use in development
  """
  def error_with_trace(conn, error) do
    stacktrace     = System.stacktrace
    exception      = Exception.normalize(:error, error)
    status         = Plug.Exception.status(error)
    exception_type = exception.__struct__

    html conn, status, """
      <html>
        <h2>(#{inspect exception_type}) #{Exception.message(exception)}</h2>
        <h4>Stacktrace</h4>
        <body>
          <pre>#{Exception.format_stacktrace stacktrace}</pre>
        </body>
      </html>
    """
  end

  @doc """
  Renders View with template based on Mime Accept headers

    * conn - The Plug.Conn struct
    * view_mod - The View module to call `render/2` on
    * layout_mod - The Layout module to render
    * template - The String template name, ie "show", "index".
                 An empty list `[]` from `plug :render` automatically assigns
                 the template as the action_name of the connection

    * assigns - The optional dict assigns to pass to template when rendering

  ## Examples

      # Explicit rendering

      defmodule MyApp.UserController do
        use Phoenix.Controller

        def show(conn) do
          render conn, "show", name: "José"
        end
      end

      # Automatic rendering with `plug :render`

      defmodule MyApp.UserController do
        use Phoenix.Controller

        plug :action
        plug :render

        def show(conn) do
          assign(conn, :name, "José")
        end
      end


  """
  def render_view(conn, view_mod, layout_mod, template, assigns \\ [])
  def render_view(conn, view_mod, layout_mod, [], assigns) do
    render_view conn, view_mod, layout_mod, action_name(conn), assigns
  end
  def render_view(conn, view_mod, layout_mod, template, assigns) do
    template     = template || action_name(conn)
    assigns      = Dict.merge(conn.assigns, assigns)
    content_type = response_content_type(conn)
    extensions   = MIME.extensions(content_type)
    layout       = layout(conn)
    status       = conn.status || 200

    if layout do
      assigns = Dict.put_new(assigns, :within, {layout_mod, template_name(layout, extensions)})
    end

    {:safe, rendered_content} = view_mod.render(template_name(template, extensions), assigns)

    send_response(conn, status, content_type, rendered_content)
  end
  defp template_name(template, extensions)
  defp template_name(template, []), do: template
  defp template_name(template, [ext | _]), do: "#{template}.#{ext}"

  @doc """
  Finds View module based on controller_module

  ## Examples

      iex> Controller.view_module(MyApp.UserController)
      MyApp.UserView

      iex> Controller.view_module(MyApp.Admin.UserController)
      MyApp.Admin.UserView

  """
  def view_module(controller_module) do
    controller_module
    |> to_string
    |> String.replace(~r/^(.*)(Controller)$/, "\\1View")
    |> Module.concat(nil)
  end

  @doc """
  Finds Layout View module based on Controller Module

  ## Examples

      iex> Controller.layout_module(MyApp.UserController)
      MyApp.LayoutView
  """
  def layout_module(controller_module) do
    controller_module
    |> Module.split
    |> Enum.at(0)
    |> Module.concat("LayoutView")
  end
end
