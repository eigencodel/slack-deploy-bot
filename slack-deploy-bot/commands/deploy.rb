module SlackDeployBot
  module Commands
    class Deploy < SlackRubyBot::Commands::Base

      match(/(deploy|накати|задеплой) ((?<app>.+)#(?<branch>.+)|(?<app>.+)) (to|на) (?<env>.+)/i) do |client, data, match|
        catch(:exit) do
          app = match[:app]
          SlackDeployBot.check_app_present_in_config(app, client, data)
          app_config = SlackDeployBot.apps[app.to_sym]

          branch = match[:branch] || app_config[:default_branch] || DEFAULT_BRANCH
          env = match[:env]

          client.send(:logger).info "app: #{app}"
          client.send(:logger).info "branch: #{branch}"
          client.send(:logger).info "env: #{env}"

          envs = app_config[:envs].map(&:to_sym)
          envs.include?(env.to_sym)  || SlackDeployBot.say_error(client, data, "Invalid env `#{env}`, use: #{envs.join(', ')}")
          git = Utils::Git.new(app_config[:path])
          git.fetch_branches         || SlackDeployBot.say_error(client, data, "Cannot fetch branches")
          git.branch_exists?(branch) || SlackDeployBot.say_error(client, data, "Unknown git branch `#{branch}`")
          git.sync_branch(branch)    || SlackDeployBot.say_error(client, data, "Couldn't pull `#{branch}`")

          git.checkout(branch)
          username = client.users[data.user][:name]
          client.send(:logger).info "user: #{username}"
          client.say(channel: data.channel, text: "#{username} started deploying #{app}##{branch} to #{env}")
          cmd = "cd #{app_config[:path]}; #{app_config[:deploy_cmd].call(env, branch)}"
          client.send(:logger).info "command: #{cmd}"

          error_happened = false
          Utils::Subprocess.new(cmd) do |stdout, stderr, thread|
            if stdout && !stdout.empty?
              client.send(:logger).info stdout
              if stdout =~ /failed\:/ || stdout =~ /command not found/
                error_happened = true
               SlackDeployBot.say_error(client, data, "Deploy failed with error: #{stdout}. More info at logs/deploybot.log")
              end
            elsif stderr && !stderr.empty?
              client.send(:logger).error stderr
              error_happened = true
              SlackDeployBot.say_error(client, data, "Deploy failed with error: #{stderr}. More info at logs/deploybot.log")
            end
          end

          unless error_happened
            client.say(channel: data.channel, text: "#{username} finished deploying #{app}##{branch} to #{env}")
          end
        end
      end
    end
  end
end
