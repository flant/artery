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

## Admin interface

In admin interface you can list your artery endpoints and check their statuses.
You can mount admin ui to your routes via:
```ruby
mount Artery::Engine => '/artery'
```
And then you can access it by url `http(s)://{ your_app_url }/artery/`.

## Contributing
Contribution directions go here.

## License
The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
