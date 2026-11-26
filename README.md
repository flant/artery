# Artery
Main messaging system between Rails [micro]services implementing message bus pattern on NATS (for now).

## Usage
How to use my plugin.

## Installation
Add this line to your application's Gemfile:

```ruby
gem 'artery'
```

And then execute:
```bash
$ bundle
```

Or install it yourself as:
```bash
$ gem install artery
```

Then install migrations and run (if using ActiveRecord):
```bash
$ rake artery:install:migrations
$ rake db:migrate
```

## Request errors

If a subscription raises an unhandled exception, the worker reports it and runs the remaining subscriptions for that delivery. If no handler published to the request's reply inbox through `Artery.publish` during synchronous dispatch, the worker replies with `{"error":"internal_error"}`. The requester receives an `Artery::RequestError` through `on.error`.

An explicit success or error reply takes precedence over this fallback. If all handlers finish normally without replying, the requester still waits for its timeout. Replies from other processes or asynchronous jobs are outside the worker's tracking scope.

## NATS permissions

Artery works with NATS users whose permissions allow only the subjects of their service.

- Replies to `Artery.request` arrive on inbox subjects under `_INBOX.<service_name>`, or under `_INBOX` if `service_name` is not configured. Set `inbox_prefix` in `backend_config` or `ARTERY_INBOX_PREFIX` to use another prefix. A restricted user needs `subscribe` on `<prefix>.>` to receive replies, and `publish` on the prefixes of its requesters to answer them: `_INBOX.>` while they keep prefixes under `_INBOX`. NATS `allow_responses` is a narrower alternative to that `publish`, allowing only replies to received requests, limited in number and time, so a late or repeated reply is denied. With the default prefix of a service a reply subject has four tokens, `_INBOX.<service_name>.<connection>.<request>`, so an ACL such as `_INBOX.*.*` no longer matches it.
- When the server denies a publish or a subscription, the connection stays open. The error is logged and reported through the error handler as `Artery::PermissionError` with the denied subject in its context. Other server errors on an established connection, such as a failed authentication on reconnect, are reported as `Artery::BackendError`. A stale connection only reconnects, and a failure of the first connect is still raised by `Artery.connect`.
- A request to a denied subject fails with `Artery::TimeoutError` after the request timeout.
- On start, the worker waits until the server has processed its subscriptions, so a denied subscription is reported right away. A denied subscription is not retried until the connection is re-established. This includes the reply inbox, which every process subscribes to once, on its first request (unless requests use `old_style`): once the permissions are fixed, restart every process that was denied, not only the worker.

### Generating permissions

`rake artery:permissions` loads the application and prints its user entry for the `authorization.users` list of `nats.conf`. The subjects come from:

- `Artery.models`, the classes that call `artery_model`: a source model publishes its events;
- `Artery.subscriptions`: the worker subscribes to them, and a subscription requests `get`, `get_updates` and `get_all` of the watched model as its handlers and synchronization options need;
- health checks: the service's own `healthz.check` and `healthz.worker`, and `healthz.check` of `ARTERY_CHECK_ESSENTIAL_SERVICES` and of the services it subscribes to;
- the inbox prefix described above: `subscribe` on it, and `publish` on it as well when it is outside `_INBOX`, so the service can answer itself;
- outgoing routes declared by the application or by gems.

Routes requested or published directly with `Artery.request` or `Artery.publish` are not visible from models and subscriptions. Declare them, for example in an initializer; a gem declares its own the same way:

```ruby
Artery.configure do |config|
  config.add_outgoing_routes 'madison.events.new', 'license_deckhouse.license.daas_tokens'
end
```

Declare the same way the inbox prefixes of requesters outside `_INBOX` (`REPLIES.billing.>`), and `<service>.healthz.check` of a service that `artery-check <service>` checks while the service neither subscribes to it nor lists it in `ARTERY_CHECK_ESSENTIAL_SERVICES`.

Subscriptions made with `Artery.subscribe` outside models are not included, apart from the health checks of Artery itself.

The user is named after the service; pass another name as the second task argument. Nothing is read from the connection credentials. The password is a reference to a variable holding its bcrypt hash, `$<SERVICE>_PASSWORD_HASH` by default; pass another name as the first task argument. Routes are sorted and unique, so the output can be compared with the configuration by a diff. Run the task with `ARTERY_CHECK_ESSENTIAL_SERVICES` set as in the deployment.

When a source model is removed or renamed, keep its old route until the old processes are stopped and the publisher has sent the messages already queued for it.

```console
$ bundle exec rake "artery:permissions[EMERGENCY_CONTACT_PASSWORD_HASH]"
{
  "user": "emergency_contact",
  "password": $EMERGENCY_CONTACT_PASSWORD_HASH,
  "permissions": {
    "publish": {
      "allow": [
        "_INBOX.>",
        "bush.healthz.check",
        "bush.projects.get",
        "bush.projects.get_all",
        "bush.projects.get_updates",
        "emergency_contact.healthz.check"
      ]
    },
    "subscribe": {
      "allow": [
        "_INBOX.emergency_contact.>",
        "bush.project.*",
        "emergency_contact.healthz.check",
        "emergency_contact.healthz.worker"
      ]
    }
  }
}
```

## Publishing modes

Artery supports two modes for publishing messages to NATS:

### Inline mode (`inline_publish = true`, default)

Messages are published directly from the `after_commit` callback. No additional processes required -- convenient for development and testing. However, under high concurrency `after_commit` callbacks can execute out of order across transactions, which may lead to incorrect `_previous_index` values. **Recommended for development only.**

### Publisher mode (`inline_publish = false`)

A separate Publisher process polls `artery_messages` and publishes them to NATS in strict `id` order, guaranteeing a correct `_previous_index` chain. Messages are persisted inside the model transaction (`before_commit`) without any locks, so there is no contention overhead. **Recommended for production.**

```ruby
Artery.configure do |config|
  config.inline_publish = false
end
```

Running the publisher:

```bash
$ bundle exec artery-publisher
```

The publisher uses a `concurrent-ruby` thread pool. Pool size is controlled by `RAILS_MAX_THREADS` (default 5). Each model gets its own thread that polls for unpublished messages.

## Admin interface

In admin interface you can list your artery endpoints and check their statuses.
You can mount admin ui to your routes via:
```ruby
mount Artery::Engine => '/artery'
```
And then you can access it by url `http(s)://{ your_app_url }/artery/`.

## Logging

Artery uses `ActiveSupport::Notifications` for instrumentation and `ActiveSupport::TaggedLogging` for request-scoped log tagging.

### Configuration

```ruby
Artery.configure do |config|
  config.service_name = :my_service

  # When true, messages are published inline from after_commit (no publisher needed).
  # Set to false in production when running the publisher process.
  # Default: true
  config.inline_publish = false

  # Log every message (publish/request/subscribe/response).
  # When false, only lifecycle events (errors, sync, connect/disconnect) are logged.
  # Default: true
  config.log_messages = true

  # Maximum bytes of message body included in logs.
  # nil = no limit (full dumps). Default: nil
  config.message_body_max_size = 1024
end
```

### Log levels

| Level | What is logged |
|-------|----------------|
| `debug` | Message payloads (request, publish, received, response), skip reasons, sync page details |
| `info` | Lifecycle events: backend connected/reconnected, worker started, sync started/completed |
| `warn` | Backend disconnected, request errors, no subscriptions defined |
| `error` | Exception handling (via `ErrorHandler`/`SentryErrorHandler`), errors sent by the backend server |

### Request-scoped tagging

All logs emitted during message processing are automatically tagged with the request ID (`reply_to` or a generated hex ID). This includes nested operations (enrich, sub-requests) and any Rails logs (e.g., ActiveRecord queries) that go through the shared logger:

```
[Artery] [Worker] [abc123] [INBOX.xyz789] [RECV] <svc.model.update> {"uuid":"..."}
[Artery] [Worker] [abc123] [INBOX.xyz789]   Source Load (0.5ms)  SELECT ...
[Artery] [Worker] [abc123] [INBOX.xyz789] [DONE] <svc.model.update> (12.3ms)
```

On Rails 7.0+ with `config.active_support.isolation_level = :fiber`, this tagging is fiber-safe.

### Instrumentation events

All events follow the `event_name.artery` convention. You can subscribe to them for metrics, tracing, or custom logging:

```ruby
ActiveSupport::Notifications.subscribe('request.artery') do |event|
  StatsD.measure('artery.request', event.duration, tags: { route: event.payload[:route] })
end
```

Available events (each uses a `stage:`, `state:`, or `action:` payload key to distinguish sub-stages):

| Event | Key | Values | Other payload | Description |
|-------|-----|--------|---------------|-------------|
| `request.artery` | `stage` | `:sent` | `route`, `data` | Outbound request sent |
| | | `:response` | `route`, `data` | Response received |
| | | `:error` | `route`, `error` | Request timeout or error (always logged) |
| `publish.artery` | — | — | `route`, `data` | Fire-and-forget publish |
| `message.artery` | `stage` | `:received` | `route`, `data`, `request_id` | Incoming message |
| | | `:handled` | `route`, `request_id` | Finished processing (block, has duration) |
| | | `:skipped` | `reason` | Message skipped |
| `sync.artery` | `stage` | `:receive_all` | `route` | Full sync (block, has duration) |
| | | `:receive_updates` | `route` | Incremental sync (block, has duration) |
| | | `:page` | `route`, `page` | Page received |
| | | `:continue` | — | Not all updates received, continuing |
| `connection.artery` | `state` | `:connected` | `server` | Connected to backend |
| | | `:disconnected` | — | Disconnected from backend |
| | | `:reconnected` | `server` | Reconnected to backend |
| | | `:closed` | — | Connection closed |
| | | `:error` | `error`, `subject` | Error sent by the server; `subject` is set for a denied publish or subscription |
| `worker.artery` | `action` | `:started` | `worker_id` | Worker started |
| | | `:subscribing` | `route` | Subscribing to route |
| `lock.artery` | `state` | `:waiting` | `latest_index` | Waiting for subscription lock |
| | | `:acquired` | `latest_index` | Lock acquired |
| `publisher.artery` | `action` | `:started` | — | Publisher loop started |
| | | `:model_started` | `model` | Model polling thread started |
| | | `:publishing` | `model`, `count` | Batch published (block, has duration) |
| | | `:error` | `model`, `error` | Publisher error for model |

## Contributing
Contribution directions go here.

## License
The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
